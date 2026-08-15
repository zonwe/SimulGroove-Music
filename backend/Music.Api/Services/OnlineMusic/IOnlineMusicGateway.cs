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
    TooLarge
}

public sealed class OnlineMusicGatewayException(
    OnlineMusicGatewayFailure failure,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public OnlineMusicGatewayFailure Failure { get; } = failure;
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
