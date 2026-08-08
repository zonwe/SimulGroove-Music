using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Music.Api.Models;

namespace Music.Api.Services.OnlineMusic;

public sealed class GoMusicDlGateway : IOnlineMusicGateway
{
    private const long MaxResponseBytes = 2 * 1024 * 1024;

    private readonly HttpClient _client;
    private readonly int _maxLyricsBytes;
    private readonly int _maxArtworkBytes;

    public GoMusicDlGateway(HttpClient client, IOptions<OnlineMusicOptions> options)
    {
        var settings = options.Value;
        if (!Uri.TryCreate(settings.SidecarBaseUrl, UriKind.Absolute, out var baseAddress) ||
            (baseAddress.Scheme != Uri.UriSchemeHttp && baseAddress.Scheme != Uri.UriSchemeHttps))
        {
            throw new InvalidOperationException("OnlineMusic:SidecarBaseUrl 必须是有效的 HTTP(S) 地址。");
        }

        _client = client;
        _client.BaseAddress = new Uri($"{baseAddress.ToString().TrimEnd('/')}/");
        _client.Timeout = TimeSpan.FromSeconds(Math.Clamp(settings.RequestTimeoutSeconds, 1, 60));
        _maxLyricsBytes = Math.Clamp(settings.MaxLyricsBytes, 4 * 1024, 2 * 1024 * 1024);
        _maxArtworkBytes = Math.Clamp(settings.MaxArtworkBytes, 16 * 1024, 8 * 1024 * 1024);
    }

    public async Task<OnlineMusicSearchResponse> SearchAsync(
        OnlineMusicSearchQuery query,
        CancellationToken cancellationToken)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "integration/v1/search")
            {
                Content = JsonContent.Create(new SidecarSearchRequest(query.Query, query.Sources, query.Limit, query.Cursor))
            };
            using var response = await _client.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.Unavailable,
                    $"go-music-dl sidecar returned HTTP {(int)response.StatusCode}.");
            }

            if (response.Content.Headers.ContentLength is > MaxResponseBytes)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidResponse,
                    "go-music-dl sidecar response exceeded the configured size limit.");
            }

            var payload = await response.Content.ReadFromJsonAsync<SidecarSearchResponse>(
                cancellationToken: cancellationToken);
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
        catch (HttpRequestException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Unavailable,
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
        try
        {
            var path = $"integration/v1/tracks/{Uri.EscapeDataString(source)}/{Uri.EscapeDataString(trackId)}/resolve";
            using var response = await _client.PostAsync(path, null, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.Unavailable,
                    $"go-music-dl sidecar resolve returned HTTP {(int)response.StatusCode}.");
            }

            var payload = await response.Content.ReadFromJsonAsync<SidecarResolveResponse>(
                cancellationToken: cancellationToken);
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
        catch (HttpRequestException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Unavailable,
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
                cancellationToken);
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
                response.Dispose();
                response = null;
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.Unavailable,
                    $"go-music-dl sidecar stream returned HTTP {(int)statusCode}.");
            }

            var content = await response.Content.ReadAsStreamAsync(cancellationToken);
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
        catch (HttpRequestException exception)
        {
            response?.Dispose();
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Unavailable,
                "go-music-dl sidecar is unavailable.",
                exception);
        }
    }

    public async Task<OnlineMusicLyricsAsset> GetLyricsAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken)
    {
        try
        {
            var path = AssetPath(source, trackId, "lyrics");
            using var response = await _client.GetAsync(path, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            EnsureAssetStatus(response, "lyrics");
            var bytes = await ReadLimitedBytesAsync(response.Content, _maxLyricsBytes, cancellationToken);
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
        catch (HttpRequestException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Unavailable,
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
        try
        {
            var path = AssetPath(source, trackId, "cover");
            using var response = await _client.GetAsync(path, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            EnsureAssetStatus(response, "cover");
            var contentType = response.Content.Headers.ContentType?.MediaType?.Trim();
            if (string.IsNullOrWhiteSpace(contentType) ||
                !contentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase))
            {
                throw new OnlineMusicGatewayException(
                    OnlineMusicGatewayFailure.InvalidResponse,
                    "go-music-dl sidecar returned an invalid artwork content type.");
            }
            var bytes = await ReadLimitedBytesAsync(response.Content, _maxArtworkBytes, cancellationToken);
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
        catch (HttpRequestException exception)
        {
            throw new OnlineMusicGatewayException(
                OnlineMusicGatewayFailure.Unavailable,
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

    private static string AssetPath(string source, string trackId, string asset) =>
        $"integration/v1/tracks/{Uri.EscapeDataString(source)}/{Uri.EscapeDataString(trackId)}/{asset}";

    private static void EnsureAssetStatus(HttpResponseMessage response, string asset)
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
                $"go-music-dl sidecar {asset} returned HTTP {(int)response.StatusCode}.");
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
}
