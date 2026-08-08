using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Models;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
public sealed class OnlineMusicSearchServiceTests
{
    [TestMethod]
    public async Task SearchCachesIdenticalQueries()
    {
        var gateway = new FakeGateway(new OnlineMusicSearchResponse(
            [new OnlineMusicTrackResponse("source-a", "1", "Song", ["Artist"], "Album", 1000, null, true, ["playback"])],
            false,
            [],
            null));
        using var cache = new MemoryCache(new MemoryCacheOptions());
        var service = CreateService(gateway, cache);
        var query = new OnlineMusicSearchQuery("Song", ["source-a"], 20, null);

        await service.SearchAsync(query, CancellationToken.None);
        await service.SearchAsync(query, CancellationToken.None);

        Assert.AreEqual(1, gateway.CallCount);
    }

    [TestMethod]
    public async Task SearchTreatsAllSourceWarningsAsUnavailable()
    {
        var gateway = new FakeGateway(new OnlineMusicSearchResponse(
            [],
            false,
            [new OnlineMusicWarningResponse("source-a", "online_music_source_unavailable", "Unavailable")],
            null));
        using var cache = new MemoryCache(new MemoryCacheOptions());
        var service = CreateService(gateway, cache);

        var exception = await Assert.ThrowsAsync<OnlineMusicSearchException>(() =>
            service.SearchAsync(
                new OnlineMusicSearchQuery("Song", ["source-a"], 20, null),
                CancellationToken.None));

        Assert.AreEqual(OnlineMusicSearchFailure.Unavailable, exception.Failure);
    }

    private static OnlineMusicSearchService CreateService(
        IOnlineMusicGateway gateway,
        IMemoryCache cache) => new(
            gateway,
            cache,
            Options.Create(new OnlineMusicOptions
            {
                Enabled = true,
                AllowedSources = ["source-a", "source-b"],
                SearchCacheSeconds = 60,
                MaxResults = 50
            }));

    private sealed class FakeGateway(OnlineMusicSearchResponse response) : IOnlineMusicGateway
    {
        public int CallCount { get; private set; }

        public Task<OnlineMusicSearchResponse> SearchAsync(
            OnlineMusicSearchQuery query,
            CancellationToken cancellationToken)
        {
            CallCount++;
            return Task.FromResult(response);
        }

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
