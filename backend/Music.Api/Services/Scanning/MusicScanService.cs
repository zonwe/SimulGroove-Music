using Music.Api.Data;
using Music.Api.Models;

namespace Music.Api.Services.Scanning;

public sealed class MusicScanService : IMusicScanService
{
    private static readonly HashSet<string> SupportedExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".mp3", ".flac", ".m4a", ".aac", ".wav", ".ogg", ".opus", ".wma"
    };

    private readonly IScanSourceStore _store;
    private readonly IAuditLogStore _audit;
    private readonly ILogger<MusicScanService> _logger;
    private readonly string[] _allowedRoots;

    public MusicScanService(IScanSourceStore store, IAuditLogStore audit, IConfiguration configuration, ILogger<MusicScanService> logger)
    {
        _store = store;
        _audit = audit;
        _logger = logger;
        _allowedRoots = configuration.GetSection("Scanning:AllowedRoots").Get<string[]>() ?? [];
    }

    public IReadOnlyList<ScanSourceResponse> GetSources(string username) => _store.GetForUser(username);

    public IReadOnlyList<ScannedTrackResponse> GetTracks(string username, string sourceId, int limit) =>
        _store.GetTracks(username, sourceId, limit);

    public ScanSourceResponse CreateSource(string username, CreateScanSourceRequest request)
    {
        var path = ValidatePath(request.Path);
        var interval = ValidateInterval(request.IntervalMinutes ?? 60);
        return _store.Create(username, path, interval, request.Enabled ?? true);
    }

    public ScanSourceResponse? UpdateSource(string username, string id, UpdateScanSourceRequest request)
    {
        var existing = _store.Get(username, id);
        if (existing is null) return null;
        var path = ValidatePath(request.Path ?? existing.Path);
        var interval = ValidateInterval(request.IntervalMinutes ?? existing.IntervalMinutes);
        return _store.Update(username, id, path, interval, request.Enabled ?? existing.Enabled);
    }

    public bool DeleteSource(string username, string id) => _store.Delete(username, id);

    public async Task<ScanSourceResponse?> ScanNowAsync(string username, string id, CancellationToken cancellationToken)
    {
        var source = _store.Get(username, id);
        if (source is null) return null;
        if (!_store.TryStartScan(id)) return _store.Get(username, id);

        var runId = Guid.NewGuid().ToString("N");
        try
        {
            var discovered = await Task.Run(() => Discover(source.Path, cancellationToken), cancellationToken);
            var completedAt = DateTimeOffset.UtcNow;
            _store.CompleteScan(id, runId, discovered, completedAt);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            _store.FailScan(id, "Scan cancelled.", DateTimeOffset.UtcNow);
            throw;
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Music scan failed for {Path}.", source.Path);
            _store.FailScan(id, exception.Message, DateTimeOffset.UtcNow);
        }

        return _store.Get(username, id);
    }

    public async Task ScanDueAsync(CancellationToken cancellationToken)
    {
        foreach (var source in _store.GetDue(DateTimeOffset.UtcNow))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var result = await ScanNowAsync(source.Username, source.Id, cancellationToken);
            if (result is not null)
            {
                var level = result.Status == "failed" ? "error" : "information";
                _audit.Record(new AuditLogEntry(source.Username, level, "scan.scheduled", $"Scheduled scan finished with status {result.Status}.", DateTimeOffset.UtcNow, Details: $"{{\"sourceId\":\"{result.Id}\",\"trackCount\":{result.TrackCount}}}"));
            }
        }
    }

    private IReadOnlyList<DiscoveredTrack> Discover(string path, CancellationToken cancellationToken)
    {
        if (!Directory.Exists(path)) throw new DirectoryNotFoundException($"Directory does not exist: {path}");
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            ReturnSpecialDirectories = false,
            AttributesToSkip = FileAttributes.ReparsePoint
        };
        var result = new List<DiscoveredTrack>();
        foreach (var filePath in Directory.EnumerateFiles(path, "*", options))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var extension = Path.GetExtension(filePath);
            if (!SupportedExtensions.Contains(extension)) continue;
            try
            {
                var file = new FileInfo(filePath);
                var albumDirectory = file.Directory;
                var artistDirectory = albumDirectory?.Parent;
                result.Add(new DiscoveredTrack(
                    file.FullName,
                    Path.GetFileNameWithoutExtension(file.Name),
                    artistDirectory?.Name ?? "Unknown Artist",
                    albumDirectory?.Name ?? "Unknown Album",
                    extension.TrimStart('.').ToLowerInvariant(),
                    file.Length,
                    new DateTimeOffset(file.LastWriteTimeUtc, TimeSpan.Zero)));
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                // A single unreadable file must not fail the whole source scan.
            }
        }
        return result;
    }

    private string ValidatePath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) throw new ArgumentException("path is required.");
        var fullPath = Path.GetFullPath(path.Trim().Trim('"'));
        if (!Directory.Exists(fullPath)) throw new ArgumentException("The directory does not exist or is not accessible.");
        if (_allowedRoots.Length == 0) return fullPath;

        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        var allowed = _allowedRoots.Any(root =>
        {
            var fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            return fullPath.Equals(fullRoot, comparison) || fullPath.StartsWith(fullRoot + Path.DirectorySeparatorChar, comparison);
        });
        if (!allowed) throw new ArgumentException("The directory is outside the configured scanning roots.");
        return fullPath;
    }

    private static int ValidateInterval(int value)
    {
        if (value is < 1 or > 10_080) throw new ArgumentException("intervalMinutes must be between 1 and 10080.");
        return value;
    }
}
