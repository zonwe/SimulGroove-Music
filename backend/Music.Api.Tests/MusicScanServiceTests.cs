using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Data;
using Music.Api.Models;
using Music.Api.Services.Scanning;

namespace Music.Api.Tests;

[TestClass]
public sealed class MusicScanServiceTests
{
    private TestDirectory _directory = null!;

    [TestInitialize]
    public void SetUp() => _directory = new TestDirectory();

    [TestCleanup]
    public void TearDown() => _directory.Dispose();

    [TestMethod]
    public async Task ScanNowIndexesSupportedFilesAndDerivesMetadata()
    {
        var allowedRoot = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Allowed")).FullName;
        var album = Directory.CreateDirectory(System.IO.Path.Combine(allowedRoot, "Artist", "Album")).FullName;
        await File.WriteAllBytesAsync(System.IO.Path.Combine(album, "Track One.mp3"), [1, 2, 3]);
        await File.WriteAllBytesAsync(System.IO.Path.Combine(album, "cover.jpg"), [1, 2, 3]);

        var store = new FakeScanSourceStore();
        var scanner = CreateScanner(store, allowedRoot);
        var source = scanner.CreateSource("alice", new CreateScanSourceRequest(allowedRoot, 60, true));

        var result = await scanner.ScanNowAsync("alice", source.Id, CancellationToken.None);

        Assert.IsNotNull(result);
        Assert.AreEqual("idle", result!.Status);
        Assert.AreEqual(1, result.TrackCount);
        Assert.AreEqual(1, store.CompletedTracks.Count);
        var track = store.CompletedTracks[0];
        Assert.AreEqual("Track One", track.Title);
        Assert.AreEqual("Artist", track.Artist);
        Assert.AreEqual("Album", track.Album);
        Assert.AreEqual("mp3", track.Extension);
        Assert.AreEqual(3, track.FileSize);
    }

    [TestMethod]
    public void CreateSourceRejectsPathsOutsideAllowedRootsAndInvalidIntervals()
    {
        var allowedRoot = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Allowed")).FullName;
        var outsideRoot = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Outside")).FullName;
        var scanner = CreateScanner(new FakeScanSourceStore(), allowedRoot);

        Assert.ThrowsException<ArgumentException>(() => scanner.CreateSource("alice", new CreateScanSourceRequest(outsideRoot, 60, true)));
        Assert.ThrowsException<ArgumentException>(() => scanner.CreateSource("alice", new CreateScanSourceRequest(allowedRoot, 0, true)));
        Assert.ThrowsException<ArgumentException>(() => scanner.CreateSource("alice", new CreateScanSourceRequest(allowedRoot, 10_081, true)));
    }

    [TestMethod]
    public async Task ScanNowRecordsFailureWhenDirectoryDisappears()
    {
        var root = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Library")).FullName;
        var store = new FakeScanSourceStore();
        var scanner = CreateScanner(store, root);
        var source = scanner.CreateSource("alice", new CreateScanSourceRequest(root, 60, true));
        Directory.Delete(root);

        var result = await scanner.ScanNowAsync("alice", source.Id, CancellationToken.None);

        Assert.IsNotNull(result);
        Assert.AreEqual("failed", result!.Status);
        StringAssert.Contains(result.LastError!, "does not exist");
    }

    [TestMethod]
    public async Task OpenTrackFileReturnsOnlyCurrentAccountsIndexedReadStream()
    {
        var root = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Library")).FullName;
        var filePath = System.IO.Path.Combine(root, "Track.mp3");
        await File.WriteAllBytesAsync(filePath, [1, 2, 3, 4]);
        var store = new FakeScanSourceStore();
        var scanner = CreateScanner(store, root);
        var source = scanner.CreateSource("alice", new CreateScanSourceRequest(root, 60, true));
        await scanner.ScanNowAsync("alice", source.Id, CancellationToken.None);
        var indexed = scanner.GetTracks("alice", source.Id, 10).Single();

        var track = scanner.OpenTrackFile("alice", source.Id, indexed.Id);

        Assert.IsNotNull(track);
        await using (track!)
        {
            Assert.AreEqual("audio/mpeg", track.ContentType);
            Assert.AreEqual(4, track.FileSize);
            Assert.IsTrue(track.Content.CanRead);
            Assert.IsFalse(track.Content.CanWrite);
            using var output = new MemoryStream();
            await track.Content.CopyToAsync(output);
            CollectionAssert.AreEqual(new byte[] { 1, 2, 3, 4 }, output.ToArray());
        }
        Assert.IsNull(scanner.OpenTrackFile("bob", source.Id, indexed.Id));

        File.Delete(filePath);
        Assert.IsNull(scanner.OpenTrackFile("alice", source.Id, indexed.Id));
    }

    [TestMethod]
    public void CreateSourceRejectsSymbolicLinkInsideAllowedRoot()
    {
        var allowedRoot = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Allowed")).FullName;
        var outsideRoot = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Outside")).FullName;
        var linkedRoot = System.IO.Path.Combine(allowedRoot, "Linked");
        try
        {
            Directory.CreateSymbolicLink(linkedRoot, outsideRoot);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or PlatformNotSupportedException)
        {
            Assert.Inconclusive($"This host cannot create a directory symbolic link: {exception.Message}");
        }
        var scanner = CreateScanner(new FakeScanSourceStore(), allowedRoot);

        var argumentException = Assert.ThrowsException<ArgumentException>(() =>
            scanner.CreateSource("alice", new CreateScanSourceRequest(linkedRoot, 60, true)));

        StringAssert.Contains(argumentException.Message, "symbolic link or reparse point");
    }

    [TestMethod]
    public async Task ExistingSourceCannotStreamOrRescanAfterAllowedRootsAreTightened()
    {
        var originalRoot = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Original")).FullName;
        var restrictedRoot = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Restricted")).FullName;
        var filePath = System.IO.Path.Combine(originalRoot, "Track.mp3");
        await File.WriteAllBytesAsync(filePath, [1, 2, 3, 4]);
        var store = new FakeScanSourceStore();
        var originalScanner = CreateScanner(store, originalRoot);
        var source = originalScanner.CreateSource("alice", new CreateScanSourceRequest(originalRoot, 60, true));
        await originalScanner.ScanNowAsync("alice", source.Id, CancellationToken.None);
        var indexed = originalScanner.GetTracks("alice", source.Id, 10).Single();
        var restrictedScanner = CreateScanner(store, restrictedRoot);

        Assert.IsNull(restrictedScanner.OpenTrackFile("alice", source.Id, indexed.Id));
        var result = await restrictedScanner.ScanNowAsync("alice", source.Id, CancellationToken.None);

        Assert.IsNotNull(result);
        Assert.AreEqual("failed", result!.Status);
        StringAssert.Contains(result.LastError!, "outside the configured scanning roots");
    }

    [TestMethod]
    public async Task ExistingSourceCannotStreamOrRescanAfterDirectoryBecomesSymbolicLink()
    {
        var allowedRoot = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Allowed")).FullName;
        var sourceRoot = Directory.CreateDirectory(System.IO.Path.Combine(allowedRoot, "Library")).FullName;
        var outsideRoot = Directory.CreateDirectory(System.IO.Path.Combine(_directory.Path, "Outside")).FullName;
        var movedRoot = System.IO.Path.Combine(outsideRoot, "Library");
        var filePath = System.IO.Path.Combine(sourceRoot, "Track.mp3");
        await File.WriteAllBytesAsync(filePath, [1, 2, 3, 4]);
        var store = new FakeScanSourceStore();
        var scanner = CreateScanner(store, allowedRoot);
        var source = scanner.CreateSource("alice", new CreateScanSourceRequest(sourceRoot, 60, true));
        await scanner.ScanNowAsync("alice", source.Id, CancellationToken.None);
        var indexed = scanner.GetTracks("alice", source.Id, 10).Single();
        Directory.Move(sourceRoot, movedRoot);
        try
        {
            Directory.CreateSymbolicLink(sourceRoot, movedRoot);
        }
        catch (Exception linkException) when (
            linkException is IOException or UnauthorizedAccessException or PlatformNotSupportedException)
        {
            Assert.Inconclusive($"This host cannot create a directory symbolic link: {linkException.Message}");
        }

        Assert.IsNull(scanner.OpenTrackFile("alice", source.Id, indexed.Id));
        var result = await scanner.ScanNowAsync("alice", source.Id, CancellationToken.None);

        Assert.IsNotNull(result);
        Assert.AreEqual("failed", result!.Status);
        StringAssert.Contains(result.LastError!, "symbolic link or reparse point");
    }

    private MusicScanService CreateScanner(FakeScanSourceStore store, string allowedRoot) => new(
        store,
        new FakeAuditLogStore(),
        new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Scanning:AllowedRoots:0"] = allowedRoot
        }).Build(),
        NullLogger<MusicScanService>.Instance);
}

internal sealed class FakeScanSourceStore : IScanSourceStore
{
    private ScanSourceResponse? _source;
    private readonly List<ScannedTrackResponse> _tracks = [];

    public List<DiscoveredTrack> CompletedTracks { get; } = [];

    public IReadOnlyList<ScanSourceResponse> GetForUser(string username) =>
        _source is { } source && source.Id.StartsWith(username, StringComparison.Ordinal) ? [source] : [];

    public IReadOnlyList<ScheduledScanSource> GetDue(DateTimeOffset now) => [];

    public ScanSourceResponse? Get(string username, string id) =>
        _source is { } source && source.Id == id && source.Id.StartsWith(username, StringComparison.Ordinal) ? source :
        _source is { } existing && existing.Id == id ? existing : null;

    public ScanSourceResponse Create(string username, string path, int intervalMinutes, bool enabled)
    {
        _source = new ScanSourceResponse($"{username}-source", path, intervalMinutes, enabled, "idle", 0, null, DateTimeOffset.UtcNow.AddMinutes(intervalMinutes), null);
        return _source;
    }

    public ScanSourceResponse? Update(string username, string id, string path, int intervalMinutes, bool enabled) =>
        _source is { Id: var sourceId } source && sourceId == id
            ? _source = source with { Path = path, IntervalMinutes = intervalMinutes, Enabled = enabled }
            : null;

    public bool Delete(string username, string id) => false;

    public bool TryStartScan(string id)
    {
        if (_source is not { Id: var sourceId } source || sourceId != id || source.Status == "scanning") return false;
        _source = source with { Status = "scanning" };
        return true;
    }

    public void CompleteScan(string id, string runId, IReadOnlyList<DiscoveredTrack> tracks, DateTimeOffset completedAt)
    {
        CompletedTracks.Clear();
        CompletedTracks.AddRange(tracks);
        _tracks.Clear();
        _tracks.AddRange(tracks.Select((track, index) => new ScannedTrackResponse(
            $"{id}-track-{index}",
            id,
            track.FilePath,
            track.Title,
            track.Artist,
            track.Album,
            track.Extension,
            track.FileSize,
            track.ModifiedAt)));
        _source = _source! with { Status = "idle", TrackCount = tracks.Count, LastScanAt = completedAt, NextScanAt = completedAt.AddMinutes(_source.IntervalMinutes), LastError = null };
    }

    public void FailScan(string id, string error, DateTimeOffset failedAt)
    {
        _source = _source! with { Status = "failed", LastError = error, LastScanAt = failedAt, NextScanAt = failedAt.AddMinutes(_source.IntervalMinutes) };
    }

    public IReadOnlyList<ScannedTrackResponse> GetTracks(string username, string sourceId, int limit) =>
        _source is { Id: var id } && id == sourceId && id.StartsWith(username, StringComparison.Ordinal)
            ? _tracks.Take(limit).ToArray()
            : [];

    public ScannedTrackResponse? GetTrack(string username, string sourceId, string trackId) =>
        GetTracks(username, sourceId, int.MaxValue).SingleOrDefault(track => track.Id == trackId);
}

internal sealed class FakeAuditLogStore : IAuditLogStore
{
    public List<AuditLogEntry> Entries { get; } = [];
    public void Record(AuditLogEntry entry) => Entries.Add(entry);

    public AuditLogPageResponse Query(string username, string? level, string? eventType, string? search, DateTimeOffset? from, DateTimeOffset? to, int page, int pageSize) =>
        new([], 0, page, pageSize);
}
