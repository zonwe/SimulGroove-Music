using System.Text;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Data;
using Music.Api.Endpoints;
using Music.Api.Models;
using Music.Api.Services;

namespace Music.Api.Tests;

[TestClass]
public sealed class PlaylistEndpointsTests
{
    [TestMethod]
    public async Task SyncRouteRequiresAuthenticationWithoutCallingStore()
    {
        var store = new FakePlaylistStore();
        var (services, requestDelegate) = CreateSyncEndpoint(store);

        var context = await InvokeSyncAsync(services, requestDelegate, "{}", token: null);

        Assert.AreEqual(StatusCodes.Status401Unauthorized, context.Response.StatusCode);
        Assert.AreEqual(0, store.CallCount);
    }

    [TestMethod]
    public async Task SyncRouteBindsAuthenticatedAccountAndPayload()
    {
        var store = new FakePlaylistStore();
        var (services, requestDelegate) = CreateSyncEndpoint(store);
        const string payload = """
            {
              "playlists": [{
                "remoteId": "playlist-1",
                "name": "Road trip",
                "updatedAt": "2026-09-09T00:00:00Z",
                "tracks": []
              }],
              "likedTracks": [],
              "equalizerPresets": [],
              "deletions": [{
                "entityType": "playlist",
                "remoteKey": "playlist-old",
                "deletedAt": "2026-09-09T00:01:00Z"
              }]
            }
            """;

        var context = await InvokeSyncAsync(services, requestDelegate, payload, "alice-token");

        Assert.AreEqual(StatusCodes.Status200OK, context.Response.StatusCode);
        Assert.AreEqual(1, store.CallCount);
        Assert.AreEqual("alice", store.Username);
        Assert.AreEqual("playlist-1", store.Playlists.Single().RemoteId);
        Assert.AreEqual("playlist-old", store.Deletions.Single().RemoteKey);
    }

    [TestMethod]
    public async Task SyncRouteRejectsInvalidMatchTokensAndDeletionsBeforeStore()
    {
        var store = new FakePlaylistStore();
        var (services, requestDelegate) = CreateSyncEndpoint(store);
        const string invalidMatchToken = """
            {
              "playlists": [],
              "likedTracks": [{
                "uri": "file:///music/song.mp3",
                "title": "Song",
                "matchToken": "hmac-sha256:not-hex"
              }],
              "equalizerPresets": [],
              "deletions": []
            }
            """;

        var invalidTrack = await InvokeSyncAsync(
            services,
            requestDelegate,
            invalidMatchToken,
            "alice-token");

        Assert.AreEqual(StatusCodes.Status400BadRequest, invalidTrack.Response.StatusCode);
        invalidTrack.Response.Body.Position = 0;
        using (var reader = new StreamReader(invalidTrack.Response.Body, leaveOpen: true))
        {
            StringAssert.Contains(await reader.ReadToEndAsync(), "invalid_track_match_token");
        }

        const string invalidDeletion = """
            {
              "playlists": [],
              "likedTracks": [],
              "equalizerPresets": [],
              "deletions": [{
                "entityType": "likedTrack",
                "remoteKey": "hmac-sha256:not-hex",
                "deletedAt": "2026-09-09T00:01:00Z"
              }]
            }
            """;
        var invalidTombstone = await InvokeSyncAsync(
            services,
            requestDelegate,
            invalidDeletion,
            "alice-token");

        Assert.AreEqual(StatusCodes.Status400BadRequest, invalidTombstone.Response.StatusCode);
        Assert.AreEqual(0, store.CallCount);
    }

    private static (IServiceProvider Services, RequestDelegate RequestDelegate) CreateSyncEndpoint(
        IPlaylistStore store)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddRouting();
        services.AddSingleton<IAuthService, FakeAuthService>();
        services.AddSingleton(store);
        var serviceProvider = services.BuildServiceProvider();
        var endpoints = new TestEndpointRouteBuilder(serviceProvider);
        endpoints.MapPlaylistEndpoints();
        var endpoint = endpoints.DataSources
            .SelectMany(source => source.Endpoints)
            .OfType<RouteEndpoint>()
            .Single(candidate => string.Equals(
                candidate.RoutePattern.RawText,
                "/api/playlists/sync",
                StringComparison.Ordinal));
        return (
            serviceProvider,
            endpoint.RequestDelegate ?? throw new InvalidOperationException("Sync route has no request delegate."));
    }

    private static async Task<DefaultHttpContext> InvokeSyncAsync(
        IServiceProvider services,
        RequestDelegate requestDelegate,
        string payload,
        string? token)
    {
        var context = new DefaultHttpContext
        {
            RequestServices = services
        };
        context.Features.Set<IHttpRequestBodyDetectionFeature>(new RequestBodyDetectionFeature());
        var requestBytes = Encoding.UTF8.GetBytes(payload);
        context.Request.Method = HttpMethods.Post;
        context.Request.Path = "/api/playlists/sync";
        context.Request.ContentType = "application/json";
        context.Request.ContentLength = requestBytes.Length;
        context.Request.Body = new MemoryStream(requestBytes, writable: false);
        if (token is not null) context.Request.Headers.Authorization = $"Bearer {token}";
        context.Response.Body = new MemoryStream();

        await requestDelegate(context);
        return context;
    }

    private sealed class FakeAuthService : IAuthService
    {
        public AuthTokenResponse? SignIn(string username, string password) => null;

        public AuthTokenResponse? Refresh(string refreshToken) => null;

        public AccountResponse? Authenticate(string? accessToken) => accessToken == "alice-token"
            ? new AccountResponse("alice-id", "alice", "Alice", null)
            : null;

        public bool RevokeAll(string accessToken) => false;
    }

    private sealed class RequestBodyDetectionFeature : IHttpRequestBodyDetectionFeature
    {
        public bool CanHaveBody => true;
    }

    private sealed class FakePlaylistStore : IPlaylistStore
    {
        public int CallCount { get; private set; }
        public string? Username { get; private set; }
        public IReadOnlyList<PlaylistRequest> Playlists { get; private set; } = [];
        public IReadOnlyList<SyncDeletionRequest> Deletions { get; private set; } = [];

        public LibrarySyncResponse SyncLibrary(
            string username,
            IReadOnlyList<PlaylistRequest> incomingPlaylists,
            IReadOnlyList<TrackRequest> incomingLikedTracks,
            IReadOnlyList<EqualizerPresetRequest> incomingEqualizerPresets,
            IReadOnlyList<SyncDeletionRequest>? incomingDeletions = null)
        {
            CallCount++;
            Username = username;
            Playlists = incomingPlaylists;
            Deletions = incomingDeletions ?? [];
            return new LibrarySyncResponse([], [], [], []);
        }
    }

    private sealed class TestEndpointRouteBuilder(IServiceProvider serviceProvider) : IEndpointRouteBuilder
    {
        public IServiceProvider ServiceProvider { get; } = serviceProvider;
        public ICollection<EndpointDataSource> DataSources { get; } = [];

        public IApplicationBuilder CreateApplicationBuilder() =>
            new ApplicationBuilder(ServiceProvider);
    }
}
