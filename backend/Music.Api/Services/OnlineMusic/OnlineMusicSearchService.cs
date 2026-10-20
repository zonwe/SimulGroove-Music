using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using Music.Api.Models;

namespace Music.Api.Services.OnlineMusic;

public enum OnlineMusicSearchFailure
{
    Disabled,

    /// <summary>sidecar 不可用、返回非成功状态或响应非法。</summary>
    ServiceUnavailable,

    /// <summary>sidecar 正常响应，但所选来源都没有可用结果。</summary>
    SourcesUnavailable,

    /// <summary>熔断器正在拒绝 search 操作，需要等待恢复窗口。</summary>
    CircuitOpen,

    Timeout
}

public sealed class OnlineMusicSearchException(
    OnlineMusicSearchFailure failure,
    string message) : Exception(message)
{
    public OnlineMusicSearchFailure Failure { get; } = failure;
}

public interface IOnlineMusicSearchService
{
    bool Enabled { get; }
    IReadOnlyList<string> AllowedSources { get; }
    int MaxResults { get; }

    Task<OnlineMusicSearchResponse> SearchAsync(
        OnlineMusicSearchQuery query,
        CancellationToken cancellationToken);
}

public sealed class OnlineMusicSearchService : IOnlineMusicSearchService
{
    private readonly IOnlineMusicGateway _gateway;
    private readonly IMemoryCache _cache;
    private readonly OnlineMusicOptions _options;

    public OnlineMusicSearchService(
        IOnlineMusicGateway gateway,
        IMemoryCache cache,
        IOptions<OnlineMusicOptions> options)
    {
        _gateway = gateway;
        _cache = cache;
        _options = options.Value;
        AllowedSources = _options.AllowedSources
            .Where(source => !string.IsNullOrWhiteSpace(source))
            .Select(source => source.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public bool Enabled => _options.Enabled;
    public IReadOnlyList<string> AllowedSources { get; }
    public int MaxResults => Math.Clamp(_options.MaxResults, 1, 100);

    public async Task<OnlineMusicSearchResponse> SearchAsync(
        OnlineMusicSearchQuery query,
        CancellationToken cancellationToken)
    {
        if (!Enabled)
        {
            throw new OnlineMusicSearchException(
                OnlineMusicSearchFailure.Disabled,
                "在线音乐功能未启用。");
        }

        var cacheKey = string.Join('|',
            query.Query,
            string.Join(',', query.Sources.Order(StringComparer.OrdinalIgnoreCase)),
            query.Limit,
            query.Cursor ?? string.Empty);
        if (_cache.TryGetValue<OnlineMusicSearchResponse>(cacheKey, out var cached) && cached is not null)
        {
            return cached;
        }

        OnlineMusicSearchResponse result;
        try
        {
            result = await _gateway.SearchAsync(query, cancellationToken);
        }
        catch (OnlineMusicGatewayException exception)
        {
            var failure = exception.Failure switch
            {
                OnlineMusicGatewayFailure.Timeout => OnlineMusicSearchFailure.Timeout,
                OnlineMusicGatewayFailure.CircuitOpen => OnlineMusicSearchFailure.CircuitOpen,
                _ => OnlineMusicSearchFailure.ServiceUnavailable
            };
            throw new OnlineMusicSearchException(failure, exception.Message);
        }

        if (result.Items.Count == 0 && result.Warnings.Count > 0)
        {
            throw new OnlineMusicSearchException(
                OnlineMusicSearchFailure.SourcesUnavailable,
                "所选在线音乐来源暂时均不可用。");
        }

        _cache.Set(
            cacheKey,
            result,
            TimeSpan.FromSeconds(Math.Clamp(_options.SearchCacheSeconds, 1, 300)));
        return result;
    }
}
