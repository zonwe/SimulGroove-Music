using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Data;
using Music.Api.Endpoints;
using Music.Api.Services;
using Music.Api.Services.Scanning;

namespace Music.Api.Tests;

[TestClass]
public sealed class ScanSourceEndpointsTests
{
    [TestMethod]
    public void RegistersIndexedTrackStreamRoute()
    {
        var services = new ServiceCollection();
        services.AddRouting();
        services.AddSingleton<IAuthService>(_ => null!);
        services.AddSingleton<IMusicScanService>(_ => null!);
        services.AddSingleton<IAuditLogStore>(_ => null!);
        var endpoints = new TestEndpointRouteBuilder(services.BuildServiceProvider());

        endpoints.MapScanSourceEndpoints();

        var routes = endpoints.DataSources
            .SelectMany(source => source.Endpoints)
            .OfType<RouteEndpoint>()
            .ToArray();
        Assert.IsTrue(routes.Any(endpoint =>
            string.Equals(
                endpoint.RoutePattern.RawText,
                "/api/scan-sources/{id}/tracks/{trackId}/stream",
                StringComparison.Ordinal) &&
            endpoint.Metadata.GetMetadata<HttpMethodMetadata>()?.HttpMethods.Contains(HttpMethods.Get) == true));
    }

    private sealed class TestEndpointRouteBuilder(IServiceProvider serviceProvider) : IEndpointRouteBuilder
    {
        public IServiceProvider ServiceProvider { get; } = serviceProvider;
        public ICollection<EndpointDataSource> DataSources { get; } = [];

        public IApplicationBuilder CreateApplicationBuilder() =>
            new ApplicationBuilder(ServiceProvider);
    }
}
