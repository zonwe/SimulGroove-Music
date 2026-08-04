using Music.Api.Models;

namespace Music.Api.Data;

public interface IScanSourceStore
{
    IReadOnlyList<ScanSourceResponse> GetForUser(string username);
    IReadOnlyList<ScheduledScanSource> GetDue(DateTimeOffset now);
    ScanSourceResponse? Get(string username, string id);
    ScanSourceResponse Create(string username, string path, int intervalMinutes, bool enabled);
    ScanSourceResponse? Update(string username, string id, string path, int intervalMinutes, bool enabled);
    bool Delete(string username, string id);
    bool TryStartScan(string id);
    void CompleteScan(string id, string runId, IReadOnlyList<DiscoveredTrack> tracks, DateTimeOffset completedAt);
    void FailScan(string id, string error, DateTimeOffset failedAt);
    IReadOnlyList<ScannedTrackResponse> GetTracks(string username, string sourceId, int limit);
}
