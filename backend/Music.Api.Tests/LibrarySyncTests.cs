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
    public void SyncLibraryKeepsStoredTracksWhenTimestampIsUnchanged()
    {
        var store = CreateStore();
        var updatedAt = DateTimeOffset.Parse("2026-08-24T08:00:00Z");
        var track = new TrackRequest(
            "file:///music/song.mp3",
            "Song",
            "Artist",
            "Album",
            120000,
            updatedAt);
        var original = new PlaylistRequest(
            "playlist-1",
            "Playlist",
            updatedAt,
            [track]);

        store.SyncLibrary("user@example.com", [original], [], []);
        var response = store.SyncLibrary(
            "user@example.com", [Playlist("playlist-1", "Playlist", updatedAt)], [], []);

        Assert.AreEqual(1, response.Playlists.Single().Tracks.Count);
        Assert.AreEqual(track.Uri, response.Playlists.Single().Tracks.Single().Uri);
    }

    [TestMethod]
    public void TrackMatchTokenValidatorRejectsMalformedValues()
    {
        Assert.IsTrue(TrackMatchTokens.IsValidOrEmpty(null));
        Assert.IsTrue(TrackMatchTokens.IsValidOrEmpty(MatchToken('a')));
        Assert.IsFalse(TrackMatchTokens.IsValidOrEmpty("sha256:" + new string('a', 64)));
        Assert.IsFalse(TrackMatchTokens.IsValidOrEmpty(
            TrackMatchTokens.Prefix + new string('A', 64)));
    }

    [TestMethod]
    public void SyncLibraryRepairsEmptyPlaylistFromRicherEqualTimestampClient()
    {
        var store = CreateStore();
        var updatedAt = DateTimeOffset.Parse("2026-08-24T08:30:00Z");
        var track = new TrackRequest(
            "file:///music/song.mp3",
            "Song",
            "Artist",
            "Album",
            120000,
            updatedAt);

        store.SyncLibrary(
            "user@example.com", [Playlist("playlist-1", "Playlist", updatedAt)], [], []);
        var response = store.SyncLibrary(
            "user@example.com",
            [new PlaylistRequest("playlist-1", "Playlist", updatedAt, [track])],
            [],
            []);

        Assert.AreEqual(1, response.Playlists.Single().Tracks.Count);
        Assert.AreEqual(track.Uri, response.Playlists.Single().Tracks.Single().Uri);
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

    [TestMethod]
    public void MatchTokenLinksLikedTrackAcrossDeviceUrisAndSupportsDeletion()
    {
        var store = CreateStore();
        var addedAt = DateTimeOffset.Parse("2026-08-24T08:00:00Z");
        var deletedAt = addedAt.AddMinutes(1);
        var token = MatchToken('a');
        var windows = new TrackRequest(
            "file:///C:/Music/song.mp3",
            "Song",
            "Artist",
            "Album",
            120000,
            addedAt,
            token);
        var android = windows with
        {
            Uri = "content://media/external/audio/media/42",
            UpdatedAt = addedAt.AddSeconds(1)
        };

        store.SyncLibrary("user@example.com", [], [windows], []);
        var synced = store.SyncLibrary("user@example.com", [], [android], []);

        Assert.AreEqual(1, synced.LikedTracks.Count);
        Assert.AreEqual(android.Uri, synced.LikedTracks.Single().Uri);
        Assert.AreEqual(token, synced.LikedTracks.Single().MatchToken);

        var deleted = store.SyncLibrary(
            "user@example.com",
            [],
            [],
            [],
            [new SyncDeletionRequest(SyncEntityTypes.LikedTrack, token, deletedAt)]);
        Assert.AreEqual(0, deleted.LikedTracks.Count);
        Assert.AreEqual(token, deleted.Deletions.Single().RemoteKey);
    }

    [TestMethod]
    public void MatchTokensAndTombstonesRemainAccountScoped()
    {
        var store = CreateStore();
        var addedAt = DateTimeOffset.Parse("2026-08-24T08:00:00Z");
        var token = MatchToken('b');
        var track = new TrackRequest(
            "file:///music/song.mp3",
            "Song",
            "Artist",
            "Album",
            120000,
            addedAt,
            token);

        store.SyncLibrary("alice@example.com", [], [track], []);
        store.SyncLibrary("bob@example.com", [], [track], []);
        store.SyncLibrary(
            "alice@example.com",
            [],
            [],
            [],
            [new SyncDeletionRequest(
                SyncEntityTypes.LikedTrack,
                token,
                addedAt.AddMinutes(1))]);

        Assert.AreEqual(
            0,
            store.SyncLibrary("alice@example.com", [], [], []).LikedTracks.Count);
        Assert.AreEqual(
            1,
            store.SyncLibrary("bob@example.com", [], [], []).LikedTracks.Count);
    }

    [TestMethod]
    public void PlaylistRoundTripPreservesMatchToken()
    {
        var store = CreateStore();
        var updatedAt = DateTimeOffset.Parse("2026-08-24T08:00:00Z");
        var token = MatchToken('c');
        var track = new TrackRequest(
            "file:///music/song.mp3",
            "Song",
            "Artist",
            "Album",
            120000,
            updatedAt,
            token);

        var response = store.SyncLibrary(
            "user@example.com",
            [new PlaylistRequest("playlist-1", "Playlist", updatedAt, [track])],
            [],
            []);

        Assert.AreEqual(
            token,
            response.Playlists.Single().Tracks.Single().MatchToken);
    }

    private static string MatchToken(char value) =>
        $"{TrackMatchTokens.Prefix}{new string(value, 64)}";

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
