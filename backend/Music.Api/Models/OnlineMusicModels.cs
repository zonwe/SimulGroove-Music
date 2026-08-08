namespace Music.Api.Models;

public sealed record OnlineMusicSearchRequest(
    string? Query,
    IReadOnlyList<string>? Sources,
    int? Limit,
    string? Cursor);

public sealed record OnlineMusicTrackResponse(
    string Provider,
    string TrackId,
    string Title,
    IReadOnlyList<string> Artists,
    string Album,
    int? DurationMs,
    string? ArtworkUrl,
    bool Playable,
    IReadOnlyList<string> Capabilities);

public sealed record OnlineMusicWarningResponse(
    string Provider,
    string Code,
    string Message);

public sealed record OnlineMusicSearchResponse(
    IReadOnlyList<OnlineMusicTrackResponse> Items,
    bool Partial,
    IReadOnlyList<OnlineMusicWarningResponse> Warnings,
    string? NextCursor);

public sealed record OnlineMusicSourcesResponse(
    bool Enabled,
    IReadOnlyList<string> Sources);

public sealed record OnlineMusicPlaybackResponse(
    string PlaybackUrl,
    DateTimeOffset ExpiresAt,
    string? MimeType);
