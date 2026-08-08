using System.Net;
using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Models;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
public sealed class OnlineMusicPlaybackServiceTests
{
    [TestMethod]
    public async Task TicketIsOpaqueBoundToAccountAndForwardsRange()
    {
        var now = new DateTimeOffset(2026, 8, 8, 12, 0, 0, TimeSpan.Zero);
        var gateway = new FakeGateway(now.AddMinutes(5));
        var service = CreateService(gateway, new TestTimeProvider(now));

        var issued = await service.IssueAsync("alice", "source-a", "track-1", CancellationToken.None);

        Assert.IsFalse(issued.PlaybackUrl.Contains("track-1", StringComparison.Ordinal));
        Assert.IsFalse(issued.PlaybackUrl.Contains("private-stream-ref", StringComparison.Ordinal));
        Assert.AreEqual(now.AddMinutes(2), issued.ExpiresAt);

        var otherAccount = await Assert.ThrowsAsync<OnlineMusicPlaybackException>(() =>
            service.OpenAsync("bob", TicketFrom(issued), "bytes=0-99", CancellationToken.None));
        Assert.AreEqual(OnlineMusicPlaybackFailure.Forbidden, otherAccount.Failure);

        await using var stream = await service.OpenAsync(
            "alice",
            TicketFrom(issued),
            "bytes=0-99",
            CancellationToken.None);
        Assert.AreEqual("private-stream-ref", gateway.OpenedStreamRef);
        Assert.AreEqual("bytes=0-99", gateway.OpenedRange);
    }

    [TestMethod]
    public async Task ExpiredTicketReturnsStableFailureWithoutOpeningSidecar()
    {
        var now = new DateTimeOffset(2026, 8, 8, 12, 0, 0, TimeSpan.Zero);
        var clock = new TestTimeProvider(now);
        var gateway = new FakeGateway(now.AddMinutes(5));
        var service = CreateService(gateway, clock);
        var issued = await service.IssueAsync("alice", "source-a", "track-1", CancellationToken.None);
        clock.UtcNow = now.AddMinutes(3);

        var exception = await Assert.ThrowsAsync<OnlineMusicPlaybackException>(() =>
            service.OpenAsync("alice", TicketFrom(issued), null, CancellationToken.None));

        Assert.AreEqual(OnlineMusicPlaybackFailure.Expired, exception.Failure);
        Assert.IsNull(gateway.OpenedStreamRef);
    }

    private static OnlineMusicPlaybackService CreateService(
        IOnlineMusicGateway gateway,
        TimeProvider clock) => new(
            gateway,
            Options.Create(new OnlineMusicOptions
            {
                Enabled = true,
                AllowedSources = ["source-a"],
                PlaybackTicketSeconds = 120
            }),
            clock);

    private static string TicketFrom(OnlineMusicPlaybackResponse response) =>
        response.PlaybackUrl[(response.PlaybackUrl.LastIndexOf('/') + 1)..];

    private sealed class TestTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public DateTimeOffset UtcNow { get; set; } = utcNow;
        public override DateTimeOffset GetUtcNow() => UtcNow;
    }

    private sealed class FakeGateway(DateTimeOffset expiresAt) : IOnlineMusicGateway
    {
        public string? OpenedStreamRef { get; private set; }
        public string? OpenedRange { get; private set; }

        public Task<OnlineMusicSearchResponse> SearchAsync(
            OnlineMusicSearchQuery query,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<OnlineMusicResolvedStream> ResolveAsync(
            string source,
            string trackId,
            CancellationToken cancellationToken) => Task.FromResult(
                new OnlineMusicResolvedStream("private-stream-ref", expiresAt, "audio/mpeg"));

        public Task<OnlineMusicStreamResponse> OpenStreamAsync(
            string streamRef,
            string? range,
            CancellationToken cancellationToken)
        {
            OpenedStreamRef = streamRef;
            OpenedRange = range;
            var response = new HttpResponseMessage(HttpStatusCode.PartialContent)
            {
                Content = new ByteArrayContent("audio"u8.ToArray())
            };
            return response.Content.ReadAsStreamAsync(cancellationToken).ContinueWith(
                task => new OnlineMusicStreamResponse(response, task.Result),
                cancellationToken,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);
        }
    }
}
