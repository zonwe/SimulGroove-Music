using System.Net;
using System.Text;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Endpoints;
using Music.Api.Models;
using Music.Api.Services;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
public sealed class OnlineMusicEndpointsTests
{
    [TestMethod]
    public void RegistersPlaybackTicketAndStreamRoutes()
    {
        var services = new ServiceCollection();
        services.AddRouting();
        services.AddSingleton<IAuthService>(_ => null!);
        services.AddSingleton<IOnlineMusicSearchService>(_ => null!);
        services.AddSingleton<IOnlineMusicRequestLimiter>(_ => null!);
        services.AddSingleton<IOnlineMusicPlaybackService>(_ => null!);
        services.AddSingleton<IOnlineMusicAssetService>(_ => null!);
        var endpoints = new TestEndpointRouteBuilder(services.BuildServiceProvider());

        endpoints.MapOnlineMusicEndpoints();

        var routes = endpoints.DataSources
            .SelectMany(source => source.Endpoints)
            .OfType<RouteEndpoint>()
            .ToArray();
        Assert.IsTrue(HasRoute(
            routes,
            "/api/online-music/tracks/{source}/{trackId}/playback",
            HttpMethods.Post));
        Assert.IsTrue(HasRoute(
            routes,
            "/api/online-music/playback/{ticket}",
            HttpMethods.Get));
        Assert.IsTrue(HasRoute(
            routes,
            "/api/online-music/tracks/{source}/{trackId}/lyrics",
            HttpMethods.Get));
        Assert.IsTrue(HasRoute(
            routes,
            "/api/online-music/tracks/{source}/{trackId}/cover",
            HttpMethods.Get));
    }

    [TestMethod]
    public async Task SearchRouteAllowsAnonymousRequestsAndCountsThemByIp()
    {
        var limiter = new RecordingLimiter(allow: true);
        var search = new FakeSearchService();

        var context = await InvokeSearchAsync(search, limiter, token: null);

        Assert.AreEqual(StatusCodes.Status200OK, context.Response.StatusCode);
        Assert.AreEqual(1, search.CallCount);
        Assert.AreEqual("夜曲", search.Query);
        Assert.AreEqual("127.0.0.1", limiter.AnonymousIp);
        Assert.IsNull(limiter.Username);
    }

    [TestMethod]
    public async Task SearchRouteRejectsAnonymousRequestsWhenIpLimitIsReached()
    {
        var limiter = new RecordingLimiter(allow: false);
        var search = new FakeSearchService();

        var context = await InvokeSearchAsync(search, limiter, token: null);

        Assert.AreEqual(StatusCodes.Status429TooManyRequests, context.Response.StatusCode);
        Assert.AreEqual(0, search.CallCount);
    }

    private static bool HasRoute(
        IEnumerable<RouteEndpoint> routes,
        string pattern,
        string method) => routes.Any(endpoint =>
            string.Equals(endpoint.RoutePattern.RawText, pattern, StringComparison.Ordinal) &&
            endpoint.Metadata.GetMetadata<HttpMethodMetadata>()?.HttpMethods.Contains(method) == true);

    private static async Task<DefaultHttpContext> InvokeSearchAsync(
        FakeSearchService search,
        RecordingLimiter limiter,
        string? token)
    {
        var services = new ServiceCollection();
        services.AddRouting();
        services.AddLogging();
        services.AddSingleton<IAuthService, FakeAuthService>();
        services.AddSingleton<IOnlineMusicSearchService>(search);
        services.AddSingleton<IOnlineMusicRequestLimiter>(limiter);
        services.AddSingleton<IOnlineMusicPlaybackService>(_ => null!);
        services.AddSingleton<IOnlineMusicAssetService>(_ => null!);
        var serviceProvider = services.BuildServiceProvider();
        var endpoints = new TestEndpointRouteBuilder(serviceProvider);
        endpoints.MapOnlineMusicEndpoints();
        var requestDelegate = endpoints.DataSources
            .SelectMany(source => source.Endpoints)
            .OfType<RouteEndpoint>()
            .Single(candidate =>
                string.Equals(
                    candidate.RoutePattern.RawText,
                    "/api/online-music/search",
                    StringComparison.Ordinal) &&
                candidate.Metadata.GetMetadata<HttpMethodMetadata>()?.HttpMethods.Contains(HttpMethods.Post) == true)
            .RequestDelegate ?? throw new InvalidOperationException("Search route has no request delegate.");

        var context = new DefaultHttpContext { RequestServices = serviceProvider };
        context.Features.Set<IHttpRequestBodyDetectionFeature>(new RequestBodyDetectionFeature());
        context.Connection.RemoteIpAddress = IPAddress.Loopback;
        var payload = Encoding.UTF8.GetBytes("""{"query":"夜曲"}""");
        context.Request.Method = HttpMethods.Post;
        context.Request.Path = "/api/online-music/search";
        context.Request.ContentType = "application/json";
        context.Request.ContentLength = payload.Length;
        context.Request.Body = new MemoryStream(payload, writable: false);
        if (token is not null) context.Request.Headers.Authorization = $"Bearer {token}";
        context.Response.Body = new MemoryStream();

        await requestDelegate(context);
        return context;
    }

    private sealed class FakeAuthService : IAuthService
    {
        public AuthTokenResponse? SignIn(string username, string password) => null;

        public AuthTokenResponse? Refresh(string refreshToken) => null;

        public AccountResponse? Authenticate(string? accessToken) => null;

        public bool RevokeAll(string accessToken) => false;
    }

    private sealed class FakeSearchService : IOnlineMusicSearchService
    {
        public bool Enabled => true;
        public IReadOnlyList<string> AllowedSources { get; } = ["netease"];
        public int MaxResults => 20;
        public int CallCount { get; private set; }
        public string? Query { get; private set; }

        public Task<OnlineMusicSearchResponse> SearchAsync(
            OnlineMusicSearchQuery query,
            CancellationToken cancellationToken)
        {
            CallCount++;
            Query = query.Query;
            return Task.FromResult(new OnlineMusicSearchResponse([], false, [], null));
        }
    }

    private sealed class RecordingLimiter(bool allow) : IOnlineMusicRequestLimiter
    {
        public string? AnonymousIp { get; private set; }
        public string? Username { get; private set; }

        public bool TryAcquire(string username, string? ipAddress)
        {
            Username = username;
            return allow;
        }

        public bool TryAcquireAnonymous(string? ipAddress)
        {
            AnonymousIp = ipAddress;
            return allow;
        }
    }

    private sealed class RequestBodyDetectionFeature : IHttpRequestBodyDetectionFeature
    {
        public bool CanHaveBody => true;
    }

    private sealed class TestEndpointRouteBuilder(IServiceProvider serviceProvider) : IEndpointRouteBuilder
    {
        public IServiceProvider ServiceProvider { get; } = serviceProvider;
        public ICollection<EndpointDataSource> DataSources { get; } = [];

        public IApplicationBuilder CreateApplicationBuilder() =>
            new ApplicationBuilder(ServiceProvider);
    }
}
