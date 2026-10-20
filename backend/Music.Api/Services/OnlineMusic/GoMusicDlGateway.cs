using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Music.Api.Models;

namespace Music.Api.Services.OnlineMusic;

public sealed class GoMusicDlGateway : IOnlineMusicGateway
{
    private const long MaxResponseBytes = 2 * 1024 * 1024;
    private const int MaxSearchAttempts = 2;

    // 重试只覆盖"还没发出请求就失败"的传输层抖动，因此固定短延迟即可，
    // 不需要指数退避；再长会把总耗时推过 Flutter 客户端的 15 秒超时。
    private static readonly TimeSpan SearchRetryDelay = TimeSpan.FromMilliseconds(200);

    private readonly HttpClient _client;
    private readonly ILogger<GoMusicDlGateway> _logger;
    private readonly TimeSpan _requestTimeout;
    private readonly int _maxLyricsBytes;
    private readonly int _maxArtworkBytes;

    public GoMusicDlGateway(
        HttpClient client,
        IOptions<OnlineMusicOptions> options,
        ILogger<GoMusicDlGateway> logger)
    {
        var settings = options.Value;
        if (!Uri.TryCreate(settings.SidecarBaseUrl, UriKind.Absolute, out var baseAddress) ||
            (baseAddress.Scheme != Uri.UriSchemeHttp && baseAddress.Scheme != Uri.UriSchemeHttps))
        {
            throw new InvalidOperationException("OnlineMusic:SidecarBaseUrl 必须是有效的 HTTP(S) 地址。");
        }

        _client = client;
        _logger = logger;
        _client.BaseAddress = new Uri($"{baseAddress.ToString().TrimEnd('/')}/");
        _client.Timeout = Timeout.InfiniteTimeSpan;
        _requestTimeout = TimeSpan.FromSeconds(Math.Clamp(settings.RequestTimeoutSeconds, 1, 60));
        _maxLyricsBytes = Math.Clamp(settings.MaxLyricsBytes, 4 * 1024, 2 * 1024 * 1024);
        _maxArtworkBytes = Math.Clamp(settings.MaxArtworkBytes, 16 * 1024, 8 * 1024 * 1024);
    }

    public async Task<OnlineMusicSearchResponse> SearchAsync(
        OnlineMusicSearchQuery query,
        CancellationToken cancellationToken)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return await SearchOnceAsync(query, cancellationToken);
            }
            catch (OnlineMusicGatewayException exception)
                when (attempt < MaxSearchAttempts && exception.Failure == OnlineMusicGatewayFailure.Transport)
            {
                // 空闲一段时间后的第一次调用最容易撞上已被对端关闭的池化连接。
                // 只重试传输层错误：业务响应重试没有意义，超时重试会把总耗时推过客户端超时。
                _logger.LogDebug(exception, "Retrying online music search after a transport failure.");
                await Task.Delay(SearchRetryDelay, cancellationToken);
            }
        }
    }

    private async Task<OnlineMusicSearchResponse> SearchOnceAsync(
        OnlineMusicSearchQuery query,
        CancellationToken cancellationToken)
    {
        using var timeout = RequestTimeout(cancellationToken, _requestTimeout);
        var requestToken = timeout.Token;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "integration/v1/search")
            {
                Content = JsonContent.Create(new SidecarSearchRequest(query.Query, query.Sources, query.Limit, query.Cursor))
            };
            using var response = await _client.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                requestToken);
            if (!response.IsSuccessStatusCode)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.Unavailable,
                    $"go-music-dl sidecar returned HTTP {(int)response.StatusCode}.",
                    upstreamCode: await TryReadErrorCodeAsync(response, requestToken));
            }

            if (response.Content.Headers.ContentLength is > MaxResponseBytes)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidResponse,
                    "go-music-dl sidecar response exceeded the configured size limit.");
            }

            var payload = await response.Content.ReadFromJsonAsync<SidecarSearchResponse>(
                cancellationToken: requestToken);
            if (payload is null)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidResponse,
                    "go-music-dl sidecar returned an empty response.");
            }

            if ((payload.Items?.Count ?? 0) == 0 &&
                payload.Warnings is { Count: > 0 } &&
                payload.Warnings.All(warning =>
                    warning.Code?.Contains("timeout", StringComparison.OrdinalIgnoreCase) == true))
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.Timeout,
                    "All go-music-dl sources timed out.");
            }

            var items = (payload.Items ?? [])
                .Where(item =>
                    !string.IsNullOrWhiteSpace(item.Source) &&
                    !string.IsNullOrWhiteSpace(item.TrackId) &&
                    !string.IsNullOrWhiteSpace(item.Title))
                .Select(item => new OnlineMusicTrackResponse(
                    item.Source!.Trim(),
                    item.TrackId!.Trim(),
                    item.Title!.Trim(),
                    (item.Artists ?? []).Where(value => !string.IsNullOrWhiteSpace(value)).Select(value => value.Trim()).ToArray(),
                    item.Album?.Trim() ?? string.Empty,
                    item.DurationMs is >= 0 ? item.DurationMs : null,
                    string.IsNullOrWhiteSpace(item.ArtworkRef)
                        ? null
                        : $"/api/online-music/tracks/{Uri.EscapeDataString(item.Source!.Trim())}/{Uri.EscapeDataString(item.TrackId!.Trim())}/cover",
                    item.Playable,
                    BuildCapabilities(item)))
                .ToArray();
            var warnings = (payload.Warnings ?? [])
                .Where(warning => !string.IsNullOrWhiteSpace(warning.Source))
                .Select(warning => new OnlineMusicWarningResponse(
                    warning.Source!.Trim(),
                    "online_music_source_unavailable",
                    "该来源暂时不可用。"))
                .ToArray();

            return new OnlineMusicSearchResponse(
                items,
                items.Length > 0 && warnings.Length > 0,
                warnings,
                payload.NextCursor);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Timeout,
                "go-music-dl sidecar request timed out.",
                exception);
        }
        catch (OnlineMusicCircuitOpenException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.CircuitOpen,
                "go-music-dl sidecar circuit is open.",
                exception);
        }
        catch (HttpRequestException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Transport,
                "go-music-dl sidecar is unavailable.",
                exception);
        }
        catch (JsonException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.InvalidResponse,
                "go-music-dl sidecar returned invalid JSON.",
                exception);
        }
    }

    public async Task<OnlineMusicResolvedStream> ResolveAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken)
    {
        using var timeout = RequestTimeout(cancellationToken, _requestTimeout);
        var requestToken = timeout.Token;
        try
        {
            var path = $"integration/v1/tracks/{Uri.EscapeDataString(source)}/{Uri.EscapeDataString(trackId)}/resolve";
            using var response = await _client.PostAsync(path, null, requestToken);
            if (!response.IsSuccessStatusCode)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.Unavailable,
                    $"go-music-dl sidecar resolve returned HTTP {(int)response.StatusCode}.",
                    upstreamCode: await TryReadErrorCodeAsync(response, requestToken));
            }

            var payload = await response.Content.ReadFromJsonAsync<SidecarResolveResponse>(
                cancellationToken: requestToken);
            if (payload is null || string.IsNullOrWhiteSpace(payload.StreamRef) || payload.ExpiresAt <= DateTimeOffset.UtcNow)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidResponse,
                    "go-music-dl sidecar returned an invalid stream reference.");
            }
            return new OnlineMusicResolvedStream(
                payload.StreamRef.Trim(),
                payload.ExpiresAt,
                string.IsNullOrWhiteSpace(payload.MimeType) ? null : payload.MimeType.Trim());
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Timeout,
                "go-music-dl sidecar resolve timed out.",
                exception);
        }
        catch (OnlineMusicCircuitOpenException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.CircuitOpen,
                "go-music-dl sidecar circuit is open.",
                exception);
        }
        catch (HttpRequestException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Transport,
                "go-music-dl sidecar is unavailable.",
                exception);
        }
        catch (JsonException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.InvalidResponse,
                "go-music-dl sidecar returned invalid JSON.",
                exception);
        }
    }

    public async Task<OnlineMusicStreamResponse> OpenStreamAsync(
        string streamRef,
        string? range,
        CancellationToken cancellationToken)
    {
        using var timeout = RequestTimeout(cancellationToken, _requestTimeout);
        var requestToken = timeout.Token;
        HttpResponseMessage? response = null;
        try
        {
            using var request = new HttpRequestMessage(
                HttpMethod.Get,
                $"integration/v1/streams/{Uri.EscapeDataString(streamRef)}");
            if (!string.IsNullOrWhiteSpace(range))
            {
                request.Headers.TryAddWithoutValidation("Range", range.Trim());
            }
            response = await _client.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                requestToken);
            if (response.StatusCode == System.Net.HttpStatusCode.RequestedRangeNotSatisfiable)
            {
                response.Dispose();
                response = null;
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidRange,
                    "go-music-dl sidecar rejected the requested range.");
            }
            if (response.StatusCode is not (System.Net.HttpStatusCode.OK or System.Net.HttpStatusCode.PartialContent))
            {
                var statusCode = response.StatusCode;
                // 先取错误码再释放响应，否则拿不到 sidecar 的业务错误分类。
                var upstreamCode = await TryReadErrorCodeAsync(response, requestToken);
                response.Dispose();
                response = null;
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.Unavailable,
                    $"go-music-dl sidecar stream returned HTTP {(int)statusCode}.",
                    upstreamCode: upstreamCode);
            }

            var content = await response.Content.ReadAsStreamAsync(requestToken);
            return new OnlineMusicStreamResponse(response, content);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            response?.Dispose();
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Timeout,
                "go-music-dl sidecar stream timed out.",
                exception);
        }
        catch (OnlineMusicCircuitOpenException exception)
        {
            response?.Dispose();
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.CircuitOpen,
                "go-music-dl sidecar circuit is open.",
                exception);
        }
        catch (HttpRequestException exception)
        {
            response?.Dispose();
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Transport,
                "go-music-dl sidecar is unavailable.",
                exception);
        }
    }

    public async Task<OnlineMusicStreamResponse> OpenDownloadAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken)
    {
        using var timeout = RequestTimeout(cancellationToken, TimeSpan.FromMinutes(3));
        var requestToken = timeout.Token;
        HttpResponseMessage? response = null;
        try
        {
            var path = AssetPath(source, trackId, "download");
            response = await _client.SendAsync(
                new HttpRequestMessage(HttpMethod.Get, path),
                HttpCompletionOption.ResponseHeadersRead,
                requestToken);
            if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                response.Dispose();
                response = null;
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.NotFound,
                    "go-music-dl sidecar track was not found.");
            }
            if (!response.IsSuccessStatusCode)
            {
                var statusCode = response.StatusCode;
                var upstreamCode = await TryReadErrorCodeAsync(response, requestToken);
                response.Dispose();
                response = null;
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.Unavailable,
                    $"go-music-dl sidecar download returned HTTP {(int)statusCode}.",
                    upstreamCode: upstreamCode);
            }
            var contentType = response.Content.Headers.ContentType?.MediaType;
            if (string.IsNullOrWhiteSpace(contentType) ||
                !contentType.StartsWith("audio/", StringComparison.OrdinalIgnoreCase))
            {
                response.Dispose();
                response = null;
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidResponse,
                    "go-music-dl sidecar returned an invalid download content type.");
            }
            var content = await response.Content.ReadAsStreamAsync(requestToken);
            return new OnlineMusicStreamResponse(response, content);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            response?.Dispose();
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Timeout,
                "go-music-dl sidecar download timed out.",
                exception);
        }
        catch (OnlineMusicCircuitOpenException exception)
        {
            response?.Dispose();
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.CircuitOpen,
                "go-music-dl sidecar circuit is open.",
                exception);
        }
        catch (HttpRequestException exception)
        {
            response?.Dispose();
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Transport,
                "go-music-dl sidecar is unavailable.",
                exception);
        }
    }

    public async Task<OnlineMusicLyricsAsset> GetLyricsAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken)
    {
        using var timeout = RequestTimeout(cancellationToken, _requestTimeout);
        var requestToken = timeout.Token;
        try
        {
            var path = AssetPath(source, trackId, "lyrics");
            using var response = await _client.GetAsync(path, HttpCompletionOption.ResponseHeadersRead, requestToken);
            await EnsureAssetStatusAsync(response, "lyrics", requestToken);
            var bytes = await ReadLimitedBytesAsync(response.Content, _maxLyricsBytes, requestToken);
            var payload = JsonSerializer.Deserialize<SidecarLyricsResponse>(
                bytes,
                new JsonSerializerOptions(JsonSerializerDefaults.Web));
            if (payload is null || string.IsNullOrWhiteSpace(payload.Lyrics))
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidResponse,
                    "go-music-dl sidecar returned invalid lyrics.");
            }
            return new OnlineMusicLyricsAsset(
                payload.Lyrics,
                string.IsNullOrWhiteSpace(payload.Format) ? "text" : payload.Format.Trim());
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Timeout,
                "go-music-dl sidecar lyrics request timed out.",
                exception);
        }
        catch (OnlineMusicCircuitOpenException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.CircuitOpen,
                "go-music-dl sidecar circuit is open.",
                exception);
        }
        catch (HttpRequestException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Transport,
                "go-music-dl sidecar is unavailable.",
                exception);
        }
        catch (JsonException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.InvalidResponse,
                "go-music-dl sidecar returned invalid lyrics JSON.",
                exception);
        }
    }

    public async Task<OnlineMusicArtworkAsset> GetArtworkAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken)
    {
        using var timeout = RequestTimeout(cancellationToken, _requestTimeout);
        var requestToken = timeout.Token;
        try
        {
            var path = AssetPath(source, trackId, "cover");
            using var response = await _client.GetAsync(path, HttpCompletionOption.ResponseHeadersRead, requestToken);
            await EnsureAssetStatusAsync(response, "cover", requestToken);
            var contentType = response.Content.Headers.ContentType?.MediaType?.Trim();
            if (string.IsNullOrWhiteSpace(contentType) ||
                !contentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase))
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidResponse,
                    "go-music-dl sidecar returned an invalid artwork content type.");
            }
            var bytes = await ReadLimitedBytesAsync(response.Content, _maxArtworkBytes, requestToken);
            if (bytes.Length == 0)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidResponse,
                    "go-music-dl sidecar returned empty artwork.");
            }
            return new OnlineMusicArtworkAsset(bytes, contentType);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Timeout,
                "go-music-dl sidecar artwork request timed out.",
                exception);
        }
        catch (OnlineMusicCircuitOpenException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.CircuitOpen,
                "go-music-dl sidecar circuit is open.",
                exception);
        }
        catch (HttpRequestException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Transport,
                "go-music-dl sidecar is unavailable.",
                exception);
        }
    }

    private static IReadOnlyList<string> BuildCapabilities(SidecarTrack item)
    {
        var capabilities = new List<string>();
        if (item.Playable) capabilities.Add("playback");
        if (!string.IsNullOrWhiteSpace(item.ArtworkRef)) capabilities.Add("artwork");
        if (item.LyricsAvailable) capabilities.Add("lyrics");
        return capabilities;
    }

    private static CancellationTokenSource RequestTimeout(
        CancellationToken cancellationToken,
        TimeSpan duration)
    {
        var source = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        source.CancelAfter(duration);
        return source;
    }

    private static string AssetPath(string source, string trackId, string asset) =>
        $"integration/v1/tracks/{Uri.EscapeDataString(source)}/{Uri.EscapeDataString(trackId)}/{asset}";

    /// <summary>
    /// 读取 sidecar 错误响应里的稳定错误码，用于把"这首曲目没有可用音源"之类的
    /// 业务结果翻译成精确的用户提示。任何解析问题都只返回 null，绝不掩盖原始失败。
    /// </summary>
    private static async Task<string?> TryReadErrorCodeAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken)
    {
        var mediaType = response.Content.Headers.ContentType?.MediaType;
        if (mediaType is null || !mediaType.Contains("json", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        try
        {
            var payload = await response.Content.ReadFromJsonAsync<SidecarErrorResponse>(
                cancellationToken: cancellationToken);
            var code = payload?.Code?.Trim();
            return string.IsNullOrWhiteSpace(code) ? null : code;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static async Task EnsureAssetStatusAsync(
        HttpResponseMessage response,
        string asset,
        CancellationToken cancellationToken)
    {
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.NotFound,
                $"go-music-dl sidecar {asset} was not found.");
        }
        if (response.StatusCode == System.Net.HttpStatusCode.RequestEntityTooLarge)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.TooLarge,
                $"go-music-dl sidecar {asset} exceeded the size limit.");
        }
        if (!response.IsSuccessStatusCode)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Unavailable,
                $"go-music-dl sidecar {asset} returned HTTP {(int)response.StatusCode}.",
                upstreamCode: await TryReadErrorCodeAsync(response, cancellationToken));
        }
    }

    private static async Task<byte[]> ReadLimitedBytesAsync(
        HttpContent content,
        int maximumBytes,
        CancellationToken cancellationToken)
    {
        if (content.Headers.ContentLength is > 0 && content.Headers.ContentLength > maximumBytes)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.TooLarge,
                "go-music-dl sidecar asset exceeded the configured size limit.");
        }
        await using var input = await content.ReadAsStreamAsync(cancellationToken);
        using var output = new MemoryStream();
        var buffer = new byte[16 * 1024];
        while (true)
        {
            var read = await input.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken);
            if (read == 0) break;
            if (output.Length + read > maximumBytes)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.TooLarge,
                    "go-music-dl sidecar asset exceeded the configured size limit.");
            }
            await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
        }
        return output.ToArray();
    }

    private sealed record SidecarSearchRequest(
        string Query,
        IReadOnlyList<string> Sources,
        int Limit,
        string? Cursor);

    private sealed record SidecarSearchResponse(
        IReadOnlyList<SidecarTrack>? Items,
        IReadOnlyList<SidecarWarning>? Warnings,
        string? NextCursor);

    private sealed record SidecarTrack(
        string? Source,
        string? TrackId,
        string? Title,
        IReadOnlyList<string>? Artists,
        string? Album,
        int? DurationMs,
        string? ArtworkRef,
        bool LyricsAvailable,
        bool Playable);

    private sealed record SidecarWarning(string? Source, string? Code);

    private sealed record SidecarResolveResponse(
        string? StreamRef,
        DateTimeOffset ExpiresAt,
        string? MimeType);

    private sealed record SidecarLyricsResponse(
        string? Lyrics,
        string? Format);

    private sealed record SidecarErrorResponse(string? Code);
}
