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

public sealed record ScannedTrackFile(
    string FilePath,
    string ContentType,
    long FileSize,
    DateTimeOffset ModifiedAt);

public sealed record DiscoveredTrack(
    string FilePath,
    string Title,
    string Artist,
    string Album,
    string Extension,
    long FileSize,
    DateTimeOffset ModifiedAt);

public sealed record ScheduledScanSource(string Id, string Username);
