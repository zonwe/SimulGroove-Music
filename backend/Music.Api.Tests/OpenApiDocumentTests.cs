using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.OpenApi;

namespace Music.Api.Tests;

[TestClass]
public sealed class OpenApiDocumentTests
{
    [TestMethod]
    public void SyncSchemasExposeEveryRoundTripCollection()
    {
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(OpenApiDocument.Create()));
        var schemas = document.RootElement
            .GetProperty("components")
            .GetProperty("schemas");

        AssertCollectionReferences(
            schemas.GetProperty("SyncPlaylistsRequest"),
            new Dictionary<string, string>
            {
                ["playlists"] = "#/components/schemas/Playlist",
                ["likedTracks"] = "#/components/schemas/Track",
                ["equalizerPresets"] = "#/components/schemas/EqualizerPreset",
                ["deletions"] = "#/components/schemas/SyncDeletion"
            });
        AssertCollectionReferences(
            schemas.GetProperty("LibrarySyncResponse"),
            new Dictionary<string, string>
            {
                ["playlists"] = "#/components/schemas/Playlist",
                ["likedTracks"] = "#/components/schemas/Track",
                ["equalizerPresets"] = "#/components/schemas/EqualizerPreset",
                ["deletions"] = "#/components/schemas/SyncDeletion"
            });
        AssertRequiredProperties(
            schemas.GetProperty("LibrarySyncResponse"),
            "playlists",
            "likedTracks",
            "equalizerPresets",
            "deletions");
        AssertRequiredProperties(schemas.GetProperty("Playlist"), "remoteId", "name");
        AssertRequiredProperties(schemas.GetProperty("EqualizerPreset"), "remoteId", "name");
        AssertRequiredProperties(
            schemas.GetProperty("SyncDeletion"),
            "entityType",
            "remoteKey",
            "deletedAt");

        CollectionAssert.AreEquivalent(
            new[] { "playlist", "likedTrack", "equalizerPreset" },
            schemas.GetProperty("SyncDeletion")
                .GetProperty("properties")
                .GetProperty("entityType")
                .GetProperty("enum")
                .EnumerateArray()
                .Select(value => value.GetString() ?? string.Empty)
                .ToArray());
        Assert.AreEqual(
            "^hmac-sha256:[0-9a-f]{64}$",
            schemas.GetProperty("Track")
                .GetProperty("properties")
                .GetProperty("matchToken")
                .GetProperty("pattern")
                .GetString());
    }

    private static void AssertCollectionReferences(
        JsonElement schema,
        IReadOnlyDictionary<string, string> expectedReferences)
    {
        var properties = schema.GetProperty("properties");
        foreach (var expected in expectedReferences)
        {
            Assert.AreEqual(
                expected.Value,
                properties.GetProperty(expected.Key)
                    .GetProperty("items")
                    .GetProperty("$ref")
                    .GetString(),
                $"Unexpected item schema for {expected.Key}.");
        }
    }

    private static void AssertRequiredProperties(JsonElement schema, params string[] expected)
    {
        CollectionAssert.AreEquivalent(
            expected,
            schema.GetProperty("required")
                .EnumerateArray()
                .Select(value => value.GetString() ?? string.Empty)
                .ToArray());
    }
}
