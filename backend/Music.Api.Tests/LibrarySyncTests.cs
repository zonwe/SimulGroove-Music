using Microsoft.Extensions.Configuration;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Data;
using Music.Api.Models;

namespace Music.Api.Tests;

[TestClass]
public sealed class LibrarySyncTests
{
    private TestDirectory _directory = null!;

    [TestInitialize]
    public void SetUp() => _directory = new TestDirectory();

    [TestCleanup]
    public void TearDown() => _directory.Dispose();

    [TestMethod]
    public void SyncLibraryKeepsTheNewestPlaylistVersion()
    {
        var store = CreateStore();
        var first = DateTimeOffset.Parse("2026-08-23T08:00:00Z");
        var newest = first.AddMinutes(2);
        var stale = first.AddMinutes(1);

        store.SyncLibrary("user@example.com", [Playlist("playlist-1", "First", first)], [], []);
        store.SyncLibrary("user@example.com", [Playlist("playlist-1", "Newest", newest)], [], []);
        var response = store.SyncLibrary("user@example.com", [Playlist("playlist-1", "Stale", stale)], [], []);

        Assert.AreEqual(1, response.Playlists.Count);
        Assert.AreEqual("Newest", response.Playlists[0].Name);
        Assert.AreEqual(newest, response.Playlists[0].UpdatedAt);
    }

    [TestMethod]
    public void TombstonesDeleteAllEntityTypesAndPreventStaleResurrection()
    {
        var store = CreateStore();
        var activeAt = DateTimeOffset.Parse("2026-08-23T08:00:00Z");
        var deletedAt = activeAt.AddMinutes(1);
        var resurrectedAt = deletedAt.AddMinutes(1);
        var liked = new TrackRequest("file:///song.mp3", "Song", "Artist", "Album", 120000, activeAt);
        var preset = new EqualizerPresetRequest("preset-1", "Preset", "[0]", 0, activeAt);

        store.SyncLibrary("user@example.com", [Playlist("playlist-1", "Playlist", activeAt)], [liked], [preset]);
        var deletions = new List<SyncDeletionRequest>
        {
            new(SyncEntityTypes.Playlist, "playlist-1", deletedAt),
            new(SyncEntityTypes.LikedTrack, "file:///song.mp3", deletedAt),
            new(SyncEntityTypes.EqualizerPreset, "preset-1", deletedAt),
        };

        var deleted = store.SyncLibrary("user@example.com", [], [], [], deletions);
        Assert.AreEqual(0, deleted.Playlists.Count);
        Assert.AreEqual(0, deleted.LikedTracks.Count);
        Assert.AreEqual(0, deleted.EqualizerPresets.Count);
        Assert.AreEqual(3, deleted.Deletions.Count);

        var stale = store.SyncLibrary(
            "user@example.com",
            [Playlist("playlist-1", "Stale", activeAt)],
            [liked],
            [preset]);
        Assert.AreEqual(0, stale.Playlists.Count);
        Assert.AreEqual(0, stale.LikedTracks.Count);
        Assert.AreEqual(0, stale.EqualizerPresets.Count);

        var resurrected = store.SyncLibrary(
            "user@example.com",
            [Playlist("playlist-1", "Resurrected", resurrectedAt)],
            [liked with { UpdatedAt = resurrectedAt }],
            [preset with { UpdatedAt = resurrectedAt }]);
        Assert.AreEqual("Resurrected", resurrected.Playlists.Single().Name);
        Assert.AreEqual(1, resurrected.LikedTracks.Count);
        Assert.AreEqual(1, resurrected.EqualizerPresets.Count);
        Assert.AreEqual(0, resurrected.Deletions.Count);
    }

    private static PlaylistRequest Playlist(string id, string name, DateTimeOffset updatedAt) =>
        new(id, name, updatedAt, []);

    private SqliteStore CreateStore()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Database:Path"] = Path.Combine(_directory.Path, "music.db"),
            })
            .Build();
        return new SqliteStore(configuration, new TestHostEnvironment(_directory.Path));
    }
}
