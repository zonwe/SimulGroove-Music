using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Endpoints;
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

    private static bool HasRoute(
        IEnumerable<RouteEndpoint> routes,
        string pattern,
        string method) => routes.Any(endpoint =>
            string.Equals(endpoint.RoutePattern.RawText, pattern, StringComparison.Ordinal) &&
            endpoint.Metadata.GetMetadata<HttpMethodMetadata>()?.HttpMethods.Contains(method) == true);

    private sealed class TestEndpointRouteBuilder(IServiceProvider serviceProvider) : IEndpointRouteBuilder
    {
        public IServiceProvider ServiceProvider { get; } = serviceProvider;
        public ICollection<EndpointDataSource> DataSources { get; } = [];

        public IApplicationBuilder CreateApplicationBuilder() =>
            new ApplicationBuilder(ServiceProvider);
    }
}
