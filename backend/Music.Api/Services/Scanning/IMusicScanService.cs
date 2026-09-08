using Music.Api.Models;

namespace Music.Api.Services.Scanning;

public interface IMusicScanService
{
    IReadOnlyList<ScanSourceResponse> GetSources(string username);
    IReadOnlyList<ScannedTrackResponse> GetTracks(string username, string sourceId, int limit);
    ScannedTrackFile? OpenTrackFile(string username, string sourceId, string trackId);
    ScanSourceResponse CreateSource(string username, CreateScanSourceRequest request);
    ScanSourceResponse? UpdateSource(string username, string id, UpdateScanSourceRequest request);
    bool DeleteSource(string username, string id);
    Task<ScanSourceResponse?> ScanNowAsync(string username, string id, CancellationToken cancellationToken);
    Task ScanDueAsync(CancellationToken cancellationToken);
}
