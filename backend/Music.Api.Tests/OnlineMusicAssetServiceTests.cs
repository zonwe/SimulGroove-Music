using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Models;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
public sealed class OnlineMusicAssetServiceTests
{
    [TestMethod]
    public async Task AssetsAreCachedAndArtworkGetsStableEtag()
    {
        var gateway = new FakeGateway();
        using var service = CreateService(gateway);

        var firstLyrics = await service.GetLyricsAsync("source-a", "track-1", CancellationToken.None);
        var secondLyrics = await service.GetLyricsAsync("source-a", "track-1", CancellationToken.None);
        var firstArtwork = await service.GetArtworkAsync("source-a", "track-1", CancellationToken.None);
        var secondArtwork = await service.GetArtworkAsync("source-a", "track-1", CancellationToken.None);

        Assert.AreEqual("[00:01.00]Line", firstLyrics.Lyrics);
        Assert.AreSame(firstLyrics, secondLyrics);
        Assert.AreSame(firstArtwork, secondArtwork);
        Assert.IsTrue(firstArtwork.ETag.StartsWith('"') && firstArtwork.ETag.EndsWith('"'));
        Assert.AreEqual(1, gateway.LyricsCalls);
        Assert.AreEqual(1, gateway.ArtworkCalls);
    }

    [TestMethod]
    public async Task RejectsUnlistedSourceBeforeCallingGateway()
    {
        var gateway = new FakeGateway();
        using var service = CreateService(gateway);

        var exception = await Assert.ThrowsAsync<OnlineMusicAssetException>(() =>
            service.GetLyricsAsync("other", "track-1", CancellationToken.None));

        Assert.AreEqual(OnlineMusicAssetFailure.InvalidTrack, exception.Failure);
        Assert.AreEqual(0, gateway.LyricsCalls);
    }

    private static OnlineMusicAssetService CreateService(IOnlineMusicGateway gateway) => new(
        gateway,
        Options.Create(new OnlineMusicOptions
        {
            Enabled = true,
            AllowedSources = ["source-a"],
            AssetCacheSizeBytes = 1024 * 1024,
            LyricsCacheSeconds = 60,
            ArtworkCacheSeconds = 60
        }));

    private sealed class FakeGateway : IOnlineMusicGateway
    {
        public int LyricsCalls { get; private set; }
        public int ArtworkCalls { get; private set; }

        public Task<OnlineMusicLyricsAsset> GetLyricsAsync(
            string source,
            string trackId,
            CancellationToken cancellationToken)
        {
            LyricsCalls++;
            return Task.FromResult(new OnlineMusicLyricsAsset("[00:01.00]Line", "lrc"));
        }

        public Task<OnlineMusicArtworkAsset> GetArtworkAsync(
            string source,
            string trackId,
            CancellationToken cancellationToken)
        {
            ArtworkCalls++;
            return Task.FromResult(new OnlineMusicArtworkAsset("image"u8.ToArray(), "image/jpeg"));
        }

        public Task<OnlineMusicSearchResponse> SearchAsync(
            OnlineMusicSearchQuery query,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<OnlineMusicResolvedStream> ResolveAsync(
            string source,
            string trackId,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<OnlineMusicStreamResponse> OpenStreamAsync(
            string streamRef,
            string? range,
            CancellationToken cancellationToken) => throw new NotSupportedException();
    }
}
