using Music.Api.Data;
using Music.Api.Models;

namespace Music.Api.Services.Scanning;

public sealed class MusicScanService : IMusicScanService
{
    private static readonly IReadOnlyDictionary<string, string> SupportedContentTypes =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        [".mp3"] = "audio/mpeg",
        [".flac"] = "audio/flac",
        [".m4a"] = "audio/mp4",
        [".aac"] = "audio/aac",
        [".wav"] = "audio/wav",
        [".ogg"] = "audio/ogg",
        [".opus"] = "audio/ogg",
        [".wma"] = "audio/x-ms-wma"
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

    public ScannedTrackFile? OpenTrackFile(string username, string sourceId, string trackId)
    {
        var source = _store.Get(username, sourceId);
        var track = _store.GetTrack(username, sourceId, trackId);
        if (source is null || track is null) return null;

        FileStream? content = null;
        try
        {
            var sourceRoot = Path.TrimEndingDirectorySeparator(ValidatePath(source.Path));
            var filePath = Path.GetFullPath(track.FilePath);
            if (!IsWithinRoot(filePath, sourceRoot) || HasNestedReparsePoint(filePath, sourceRoot)) return null;

            var file = new FileInfo(filePath);
            if (!file.Exists || file.Attributes.HasFlag(FileAttributes.ReparsePoint) ||
                !SupportedContentTypes.TryGetValue(file.Extension, out var contentType)) return null;

            content = new FileStream(file.FullName, new FileStreamOptions
            {
                Mode = FileMode.Open,
                Access = FileAccess.Read,
                Share = FileShare.Read,
                BufferSize = 64 * 1024,
                Options = FileOptions.Asynchronous | FileOptions.SequentialScan
            });

            // Revalidate after opening so the response owns this exact file handle
            // instead of resolving the path again after the security checks.
            file.Refresh();
            if (!file.Exists || file.Attributes.HasFlag(FileAttributes.ReparsePoint) ||
                HasNestedReparsePoint(file.FullName, sourceRoot))
            {
                content.Dispose();
                return null;
            }

            var result = new ScannedTrackFile(
                content,
                contentType,
                content.Length,
                new DateTimeOffset(file.LastWriteTimeUtc, TimeSpan.Zero));
            content = null;
            return result;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
        {
            content?.Dispose();
            _logger.LogDebug(
                exception,
                "Indexed track validation failed for source {SourceId} and track {TrackId}.",
                sourceId,
                trackId);
            return null;
        }
    }

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
            var sourcePath = ValidatePath(source.Path);
            var discovered = await Task.Run(() => Discover(sourcePath, cancellationToken), cancellationToken);
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
            if (!SupportedContentTypes.ContainsKey(extension)) continue;
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
        var fullPath = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path.Trim().Trim('"')));
        if (!Directory.Exists(fullPath)) throw new ArgumentException("The directory does not exist or is not accessible.");
        if (_allowedRoots.Length == 0)
        {
            if (HasDirectoryReparsePoint(fullPath, fullPath))
            {
                throw new ArgumentException("The scanning directory cannot be a symbolic link or reparse point.");
            }
            return fullPath;
        }

        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        var isInsideConfiguredRoot = false;
        foreach (var root in _allowedRoots)
        {
            var fullRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
            var isInsideRoot = fullPath.Equals(fullRoot, comparison) ||
                IsWithinRoot(fullPath, fullRoot);
            if (!isInsideRoot) continue;

            isInsideConfiguredRoot = true;
            if (!HasDirectoryReparsePoint(fullPath, fullRoot)) return fullPath;
        }

        if (isInsideConfiguredRoot)
        {
            throw new ArgumentException("The scanning directory path contains a symbolic link or reparse point.");
        }
        throw new ArgumentException("The directory is outside the configured scanning roots.");
    }

    private static int ValidateInterval(int value)
    {
        if (value is < 1 or > 10_080) throw new ArgumentException("intervalMinutes must be between 1 and 10080.");
        return value;
    }

    private static bool IsWithinRoot(string path, string root)
    {
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        var rootPrefix = Path.EndsInDirectorySeparator(root) ? root : root + Path.DirectorySeparatorChar;
        return path.StartsWith(rootPrefix, comparison);
    }

    private static bool HasNestedReparsePoint(string filePath, string sourceRoot)
    {
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        var directory = Directory.GetParent(filePath);
        while (directory is not null && !directory.FullName.Equals(sourceRoot, comparison))
        {
            if (directory.Attributes.HasFlag(FileAttributes.ReparsePoint)) return true;
            directory = directory.Parent;
        }
        return directory is null;
    }

    private static bool HasDirectoryReparsePoint(string directoryPath, string root)
    {
        var comparison = OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;
        DirectoryInfo? directory = new(directoryPath);
        try
        {
            while (directory is not null)
            {
                if (directory.Attributes.HasFlag(FileAttributes.ReparsePoint)) return true;
                if (directory.FullName.Equals(root, comparison)) return false;
                directory = directory.Parent;
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return true;
        }
        return true;
    }
}
