namespace Music.Api.Models;

public sealed record CreateScanSourceRequest(
    string? Path,
    int? IntervalMinutes,
    bool? Enabled);

public sealed record UpdateScanSourceRequest(
    string? Path,
    int? IntervalMinutes,
    bool? Enabled);

public sealed record ScanSourceResponse(
    string Id,
    string Path,
    int IntervalMinutes,
    bool Enabled,
    string Status,
    int TrackCount,
    DateTimeOffset? LastScanAt,
    DateTimeOffset? NextScanAt,
    string? LastError);

public sealed record ScannedTrackResponse(
    string Id,
    string ScanSourceId,
    string FilePath,
    string Title,
    string Artist,
    string Album,
    string Extension,
    long FileSize,
    DateTimeOffset ModifiedAt);

public sealed class ScannedTrackFile(
    Stream content,
    string contentType,
    long fileSize,
    DateTimeOffset modifiedAt) : IDisposable, IAsyncDisposable
{
    public Stream Content { get; } = content;
    public string ContentType { get; } = contentType;
    public long FileSize { get; } = fileSize;
    public DateTimeOffset ModifiedAt { get; } = modifiedAt;

    public void Dispose() => Content.Dispose();

    public ValueTask DisposeAsync() => Content.DisposeAsync();
}

public sealed record DiscoveredTrack(
    string FilePath,
    string Title,
    string Artist,
    string Album,
    string Extension,
    long FileSize,
    DateTimeOffset ModifiedAt);

public sealed record ScheduledScanSource(string Id, string Username);
