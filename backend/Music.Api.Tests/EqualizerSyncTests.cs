using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Data;
using Music.Api.Models;

namespace Music.Api.Tests;

[TestClass]
public sealed class EqualizerSyncTests
{
    private TestDirectory _directory = null!;

    [TestInitialize]
    public void SetUp() => _directory = new TestDirectory();

    [TestCleanup]
    public void TearDown() => _directory.Dispose();

    [TestMethod]
    public void SyncLibrarySavesAndRetrievesEqualizerPresets()
    {
        var store = CreateStore();
        var incomingPresets = new List<EqualizerPresetRequest>
        {
            new("preset-1", "My Rock", "[4.5, 3.5, 2.0, 0.0, -1.5, -1.0, 1.5, 3.0, 4.0, 4.5]", -2.0, DateTimeOffset.UtcNow),
            new("preset-2", "Vocal Plus", "[-2.0, -1.5, -1.0, 1.0, 3.5, 4.5, 3.0, 1.5, 0.0, -1.0]", -1.0, DateTimeOffset.UtcNow),
        };

        var response = store.SyncLibrary("user@example.com", [], [], incomingPresets);

        Assert.IsNotNull(response);
        Assert.AreEqual(2, response.EqualizerPresets.Count);
        var preset1 = response.EqualizerPresets.First(p => p.RemoteId == "preset-1");
        Assert.AreEqual("My Rock", preset1.Name);
        Assert.AreEqual(-2.0, preset1.PreampDb);
        Assert.IsTrue(preset1.GainsJson.Contains("4.5"));
    }

    [TestMethod]
    public void SyncLibraryUpdatesExistingEqualizerPresets()
    {
        var store = CreateStore();
        var initialPresets = new List<EqualizerPresetRequest>
        {
            new("preset-1", "Old Name", "[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]", 0.0, DateTimeOffset.UtcNow),
        };
        store.SyncLibrary("user@example.com", [], [], initialPresets);

        var updatedPresets = new List<EqualizerPresetRequest>
        {
            new("preset-1", "New Name", "[1, 2, 3, 4, 5, 4, 3, 2, 1, 0]", -1.5, DateTimeOffset.UtcNow),
        };
        var response = store.SyncLibrary("user@example.com", [], [], updatedPresets);

        Assert.AreEqual(1, response.EqualizerPresets.Count);
        Assert.AreEqual("New Name", response.EqualizerPresets[0].Name);
        Assert.AreEqual(-1.5, response.EqualizerPresets[0].PreampDb);
    }

    [TestMethod]
    public void EqualizerPresetsAreIsolatedBetweenAccounts()
    {
        var store = CreateStore();
        var user1Presets = new List<EqualizerPresetRequest>
        {
            new("preset-user1", "User 1 Preset", "[1, 1, 1, 1, 1, 1, 1, 1, 1, 1]", 0.0, DateTimeOffset.UtcNow),
        };
        var user2Presets = new List<EqualizerPresetRequest>
        {
            new("preset-user2", "User 2 Preset", "[2, 2, 2, 2, 2, 2, 2, 2, 2, 2]", 0.0, DateTimeOffset.UtcNow),
        };

        var resp1 = store.SyncLibrary("user1@example.com", [], [], user1Presets);
        var resp2 = store.SyncLibrary("user2@example.com", [], [], user2Presets);

        Assert.AreEqual(1, resp1.EqualizerPresets.Count);
        Assert.AreEqual("User 1 Preset", resp1.EqualizerPresets[0].Name);
        Assert.AreEqual(1, resp2.EqualizerPresets.Count);
        Assert.AreEqual("User 2 Preset", resp2.EqualizerPresets[0].Name);
    }

    private SqliteStore CreateStore()
    {
        var dbPath = Path.Combine(_directory.Path, "music.db");
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Database:Path"] = dbPath,
            })
            .Build();

        return new SqliteStore(configuration, new TestHostEnvironment(_directory.Path));
    }
}
