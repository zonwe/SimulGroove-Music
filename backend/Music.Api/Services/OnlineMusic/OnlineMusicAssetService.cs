using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using Music.Api.Models;

namespace Music.Api.Services.OnlineMusic;

public enum OnlineMusicAssetFailure
{
    Disabled,
    InvalidTrack,
    NotFound,
    TooLarge,
    Timeout,
    Unavailable
}

public sealed class OnlineMusicAssetException(
    OnlineMusicAssetFailure failure,
    string message) : Exception(message)
{
    public OnlineMusicAssetFailure Failure { get; } = failure;
}

public sealed record OnlineMusicArtwork(
    byte[] Bytes,
    string ContentType,
    string ETag);

public interface IOnlineMusicAssetService
{
    Task<OnlineMusicLyricsResponse> GetLyricsAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken);

    Task<OnlineMusicArtwork> GetArtworkAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken);
}

public sealed class OnlineMusicAssetService : IOnlineMusicAssetService, IDisposable
{
    private const int MaximumTrackIdLength = 512;

    private readonly IOnlineMusicGateway _gateway;
    private readonly OnlineMusicOptions _options;
    private readonly HashSet<string> _allowedSources;
    private readonly MemoryCache _cache;

    public OnlineMusicAssetService(
        IOnlineMusicGateway gateway,
        IOptions<OnlineMusicOptions> options)
    {
        _gateway = gateway;
        _options = options.Value;
        _allowedSources = _options.AllowedSources
            .Where(source => !string.IsNullOrWhiteSpace(source))
            .Select(source => source.Trim())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        _cache = new MemoryCache(new MemoryCacheOptions
        {
            SizeLimit = Math.Clamp(
                _options.AssetCacheSizeBytes,
                1024 * 1024,
                256 * 1024 * 1024)
        });
    }

    public async Task<OnlineMusicLyricsResponse> GetLyricsAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken)
    {
        (source, trackId) = ValidateTrack(source, trackId);
        var cacheKey = $"online-music:lyrics:{source}:{trackId}";
        if (_cache.TryGetValue<OnlineMusicLyricsResponse>(cacheKey, out var cached) && cached is not null)
        {
            return cached;
        }

        try
        {
            var asset = await _gateway.GetLyricsAsync(source, trackId, cancellationToken);
            var result = new OnlineMusicLyricsResponse(asset.Lyrics, asset.Format);
            var size = Math.Max(1, Encoding.UTF8.GetByteCount(asset.Lyrics));
            _cache.Set(
                cacheKey,
                result,
                new MemoryCacheEntryOptions()
                    .SetAbsoluteExpiration(TimeSpan.FromSeconds(Math.Clamp(_options.LyricsCacheSeconds, 30, 86400)))
                    .SetSize(size));
            return result;
        }
        catch (OnlineMusicGatewayException exception)
        {
            throw Map(exception);
        }
    }

    public async Task<OnlineMusicArtwork> GetArtworkAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken)
    {
        (source, trackId) = ValidateTrack(source, trackId);
        var cacheKey = $"online-music:artwork:{source}:{trackId}";
        if (_cache.TryGetValue<OnlineMusicArtwork>(cacheKey, out var cached) && cached is not null)
        {
            return cached;
        }

        try
        {
            var asset = await _gateway.GetArtworkAsync(source, trackId, cancellationToken);
            var hash = Convert.ToHexString(SHA256.HashData(asset.Bytes)).ToLowerInvariant();
            var result = new OnlineMusicArtwork(asset.Bytes, asset.ContentType, $"\"{hash}\"");
            _cache.Set(
                cacheKey,
                result,
                new MemoryCacheEntryOptions()
                    .SetAbsoluteExpiration(TimeSpan.FromSeconds(Math.Clamp(_options.ArtworkCacheSeconds, 60, 86400)))
                    .SetSize(Math.Max(1, asset.Bytes.Length)));
            return result;
        }
        catch (OnlineMusicGatewayException exception)
        {
            throw Map(exception);
        }
    }

    public void Dispose() => _cache.Dispose();

    private (string Source, string TrackId) ValidateTrack(string source, string trackId)
    {
        if (!_options.Enabled)
        {
            throw new OnlineMusicAssetException(
                OnlineMusicAssetFailure.Disabled,
                "在线音乐功能未启用。");
        }
        source = source.Trim();
        trackId = trackId.Trim();
        if (source.Length == 0 || trackId.Length == 0 || trackId.Length > MaximumTrackIdLength ||
            !_allowedSources.Contains(source))
        {
            throw new OnlineMusicAssetException(
                OnlineMusicAssetFailure.InvalidTrack,
                "歌曲来源或标识无效。");
        }
        return (source, trackId);
    }

    private static OnlineMusicAssetException Map(OnlineMusicGatewayException exception) => new(
        exception.Failure switch
        {
            OnlineMusicGatewayFailure.NotFound => OnlineMusicAssetFailure.NotFound,
            OnlineMusicGatewayFailure.TooLarge => OnlineMusicAssetFailure.TooLarge,
            OnlineMusicGatewayFailure.Timeout => OnlineMusicAssetFailure.Timeout,
            _ => OnlineMusicAssetFailure.Unavailable
        },
        exception.Message);
}
