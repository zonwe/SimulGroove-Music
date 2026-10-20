using Music.Api.Models;

namespace Music.Api.Services.OnlineMusic;

public sealed record OnlineMusicSearchQuery(
    string Query,
    IReadOnlyList<string> Sources,
    int Limit,
    string? Cursor);

public sealed record OnlineMusicResolvedStream(
    string StreamRef,
    DateTimeOffset ExpiresAt,
    string? MimeType);

public sealed record OnlineMusicLyricsAsset(
    string Lyrics,
    string Format);

public sealed record OnlineMusicArtworkAsset(
    byte[] Bytes,
    string ContentType);

public sealed class OnlineMusicStreamResponse(
    HttpResponseMessage response,
    Stream content) : IAsyncDisposable
{
    public int StatusCode { get; } = (int)response.StatusCode;
    public Stream Content { get; } = content;
    public long? ContentLength { get; } = response.Content.Headers.ContentLength;
    public string? ContentType { get; } = response.Content.Headers.ContentType?.ToString();
    public string? ContentRange { get; } = response.Content.Headers.ContentRange?.ToString();
    public string? AcceptRanges { get; } = response.Headers.AcceptRanges.FirstOrDefault();
    public string? ETag { get; } = response.Headers.ETag?.ToString();
    public string? ContentDisposition { get; } = response.Content.Headers.ContentDisposition?.ToString();
    public bool LyricsEmbedded { get; } = HeaderIsTrue(response, "X-Online-Lyrics-Embedded");
    public bool ArtworkEmbedded { get; } = HeaderIsTrue(response, "X-Online-Artwork-Embedded");

    public async ValueTask DisposeAsync()
    {
        await Content.DisposeAsync();
        response.Dispose();
    }

    private static bool HeaderIsTrue(HttpResponseMessage response, string name) =>
        response.Headers.TryGetValues(name, out var values) &&
        bool.TryParse(values.FirstOrDefault(), out var value) &&
        value;
}

public enum OnlineMusicGatewayFailure
{
    NotFound,
    Unavailable,
    Timeout,
    InvalidResponse,
    InvalidRange,
    TooLarge,

    /// <summary>传输层故障（连接被重置、DNS 失败等），是唯一值得立刻重试的类别。</summary>
    Transport,

    /// <summary>熔断器正在拒绝该操作的请求，需要等待恢复窗口。</summary>
    CircuitOpen
}

public sealed class OnlineMusicGatewayException(
    OnlineMusicGatewayFailure failure,
    string message,
    Exception? innerException = null,
    string? upstreamCode = null) : Exception(message, innerException)
{
    public OnlineMusicGatewayFailure Failure { get; } = failure;

    /// <summary>
    /// sidecar 错误响应里的稳定错误码（例如 resolve_unavailable）。仅用于把
    /// "这首曲目没有可用音源"这类业务结果翻译成精确的用户提示，不对外暴露原始报文。
    /// </summary>
    public string? UpstreamCode { get; } = upstreamCode;
}

public interface IOnlineMusicGateway
{
    Task<OnlineMusicSearchResponse> SearchAsync(
        OnlineMusicSearchQuery query,
        CancellationToken cancellationToken);

    Task<OnlineMusicResolvedStream> ResolveAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken);

    Task<OnlineMusicStreamResponse> OpenStreamAsync(
        string streamRef,
        string? range,
        CancellationToken cancellationToken);

    Task<OnlineMusicStreamResponse> OpenDownloadAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken) =>
        throw new NotSupportedException("Online downloads are not implemented by this gateway.");

    Task<OnlineMusicLyricsAsset> GetLyricsAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken);

    Task<OnlineMusicArtworkAsset> GetArtworkAsync(
        string source,
        string trackId,
        CancellationToken cancellationToken);
}
