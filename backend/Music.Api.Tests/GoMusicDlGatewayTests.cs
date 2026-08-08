using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
public sealed class GoMusicDlGatewayTests
{
    [TestMethod]
    public async Task SearchMapsSidecarContractWithoutExposingOpaqueReferences()
    {
        string? capturedPath = null;
        string? capturedBody = null;
        var handler = new StubHttpMessageHandler(async request =>
        {
            capturedPath = request.RequestUri?.AbsolutePath;
            capturedBody = await request.Content!.ReadAsStringAsync();
            var json = """
                {
                  "items": [{
                    "source": "source-a",
                    "trackId": "track-1",
                    "title": "Song",
                    "artists": ["Artist"],
                    "album": "Album",
                    "durationMs": 123000,
                    "artworkRef": "private-cover-reference",
                    "playable": true
                  }],
                  "warnings": [{"source":"source-b","code":"upstream_timeout"}],
                  "nextCursor": null
                }
                """;
            return await Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            });
        });
        var gateway = CreateGateway(handler);

        var result = await gateway.SearchAsync(
            new OnlineMusicSearchQuery("Song", ["source-a", "source-b"], 20, null),
            CancellationToken.None);

        Assert.AreEqual("/integration/v1/search", capturedPath);
        var body = JsonDocument.Parse(capturedBody!);
        Assert.AreEqual("Song", body.RootElement.GetProperty("query").GetString());
        Assert.AreEqual(2, body.RootElement.GetProperty("sources").GetArrayLength());
        Assert.AreEqual("source-a", result.Items.Single().Provider);
        Assert.IsNull(result.Items.Single().ArtworkUrl);
        CollectionAssert.Contains(result.Items.Single().Capabilities.ToArray(), "playback");
        Assert.IsTrue(result.Partial);
        Assert.AreEqual("online_music_source_unavailable", result.Warnings.Single().Code);
    }

    [TestMethod]
    public async Task SearchMapsNetworkFailureToStableGatewayFailure()
    {
        var gateway = CreateGateway(new StubHttpMessageHandler(
            _ => throw new HttpRequestException("sensitive upstream details")));

        var exception = await Assert.ThrowsAsync<OnlineMusicGatewayException>(() =>
            gateway.SearchAsync(
                new OnlineMusicSearchQuery("Song", ["source-a"], 20, null),
                CancellationToken.None));

        Assert.AreEqual(OnlineMusicGatewayFailure.Unavailable, exception.Failure);
        Assert.AreEqual("go-music-dl sidecar is unavailable.", exception.Message);
    }

    [TestMethod]
    public async Task SearchMapsAllSourceTimeoutsToTimeoutFailure()
    {
        var handler = new StubHttpMessageHandler(_ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(
                """{"items":[],"warnings":[{"source":"source-a","code":"upstream_timeout"}]}""",
                Encoding.UTF8,
                "application/json")
        }));
        var gateway = CreateGateway(handler);

        var exception = await Assert.ThrowsAsync<OnlineMusicGatewayException>(() =>
            gateway.SearchAsync(
                new OnlineMusicSearchQuery("Song", ["source-a"], 20, null),
                CancellationToken.None));

        Assert.AreEqual(OnlineMusicGatewayFailure.Timeout, exception.Failure);
    }

    [TestMethod]
    public async Task ResolveReturnsOnlyOpaqueSidecarReference()
    {
        string? capturedPath = null;
        var gateway = CreateGateway(new StubHttpMessageHandler(request =>
        {
            capturedPath = request.RequestUri?.AbsolutePath;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(
                    """{"streamRef":"private-token","expiresAt":"2099-08-08T12:00:00Z","mimeType":"audio/mpeg"}""",
                    Encoding.UTF8,
                    "application/json")
            });
        }));

        var result = await gateway.ResolveAsync("source-a", "track 1", CancellationToken.None);

        Assert.AreEqual("/integration/v1/tracks/source-a/track%201/resolve", capturedPath);
        Assert.AreEqual("private-token", result.StreamRef);
        Assert.AreEqual("audio/mpeg", result.MimeType);
    }

    [TestMethod]
    public async Task OpenStreamForwardsRangeAndKeepsResponseStreaming()
    {
        string? capturedRange = null;
        var gateway = CreateGateway(new StubHttpMessageHandler(request =>
        {
            capturedRange = request.Headers.TryGetValues("Range", out var values) ? values.Single() : null;
            var response = new HttpResponseMessage(HttpStatusCode.PartialContent)
            {
                Content = new ByteArrayContent("audio"u8.ToArray())
            };
            response.Content.Headers.ContentType = new("audio/mpeg");
            response.Content.Headers.ContentRange = new(2, 6, 10);
            return Task.FromResult(response);
        }));

        await using var stream = await gateway.OpenStreamAsync("private-token", "bytes=2-6", CancellationToken.None);
        using var reader = new StreamReader(stream.Content);

        Assert.AreEqual("bytes=2-6", capturedRange);
        Assert.AreEqual(206, stream.StatusCode);
        Assert.AreEqual("bytes 2-6/10", stream.ContentRange);
        Assert.AreEqual("audio", await reader.ReadToEndAsync());
    }

    [TestMethod]
    public async Task OpenStreamMapsRejectedRangeToStableFailure()
    {
        var gateway = CreateGateway(new StubHttpMessageHandler(_ => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.RequestedRangeNotSatisfiable))));

        var exception = await Assert.ThrowsAsync<OnlineMusicGatewayException>(() =>
            gateway.OpenStreamAsync("private-token", "bytes=999-1000", CancellationToken.None));

        Assert.AreEqual(OnlineMusicGatewayFailure.InvalidRange, exception.Failure);
    }

    private static GoMusicDlGateway CreateGateway(HttpMessageHandler handler) => new(
        new HttpClient(handler),
        Options.Create(new OnlineMusicOptions
        {
            SidecarBaseUrl = "http://127.0.0.1:8080",
            RequestTimeoutSeconds = 2
        }));

    private sealed class StubHttpMessageHandler(
        Func<HttpRequestMessage, Task<HttpResponseMessage>> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => handler(request);
    }
}
