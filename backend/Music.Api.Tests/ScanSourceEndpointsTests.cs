using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Data;
using Music.Api.Endpoints;
using Music.Api.Models;
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

    [TestMethod]
    public async Task StreamRouteRequiresBearerTokenAndHidesOtherAccounts()
    {
        var scanner = new FakeMusicScanService();
        var (services, requestDelegate) = CreateStreamEndpoint(scanner);

        var unauthorized = await InvokeStreamAsync(services, requestDelegate);

        Assert.AreEqual(StatusCodes.Status401Unauthorized, unauthorized.Response.StatusCode);
        Assert.AreEqual(0, scanner.OpenCalls);

        var otherAccount = await InvokeStreamAsync(services, requestDelegate, "bob-token");

        Assert.AreEqual(StatusCodes.Status404NotFound, otherAccount.Response.StatusCode);
        Assert.AreEqual("bob", scanner.LastUsername);
        otherAccount.Response.Body.Position = 0;
        using var reader = new StreamReader(otherAccount.Response.Body, leaveOpen: true);
        StringAssert.Contains(await reader.ReadToEndAsync(), "server_track_not_found");
    }

    [TestMethod]
    public async Task StreamRouteSupportsValidAndRejectedRanges()
    {
        var scanner = new FakeMusicScanService();
        var (services, requestDelegate) = CreateStreamEndpoint(scanner);

        var partial = await InvokeStreamAsync(
            services,
            requestDelegate,
            "alice-token",
            "bytes=1-2");

        Assert.AreEqual(StatusCodes.Status206PartialContent, partial.Response.StatusCode);
        Assert.AreEqual("bytes", partial.Response.Headers.AcceptRanges.ToString());
        Assert.AreEqual("bytes 1-2/4", partial.Response.Headers.ContentRange.ToString());
        Assert.AreEqual("private, no-store", partial.Response.Headers.CacheControl.ToString());
        partial.Response.Body.Position = 0;
        CollectionAssert.AreEqual(new byte[] { 20, 30 }, ((MemoryStream)partial.Response.Body).ToArray());

        var rejected = await InvokeStreamAsync(
            services,
            requestDelegate,
            "alice-token",
            "bytes=10-12");

        Assert.AreEqual(StatusCodes.Status416RangeNotSatisfiable, rejected.Response.StatusCode);
        Assert.AreEqual("bytes */4", rejected.Response.Headers.ContentRange.ToString());
        Assert.AreEqual(0, rejected.Response.Body.Length);
    }

    private static (IServiceProvider Services, RequestDelegate RequestDelegate) CreateStreamEndpoint(
        IMusicScanService scanner)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddRouting();
        services.AddSingleton<IAuthService, FakeAuthService>();
        services.AddSingleton(scanner);
        services.AddSingleton<IAuditLogStore>(_ => null!);
        var serviceProvider = services.BuildServiceProvider();
        var endpoints = new TestEndpointRouteBuilder(serviceProvider);
        endpoints.MapScanSourceEndpoints();
        var endpoint = endpoints.DataSources
            .SelectMany(source => source.Endpoints)
            .OfType<RouteEndpoint>()
            .Single(candidate => string.Equals(
                candidate.RoutePattern.RawText,
                "/api/scan-sources/{id}/tracks/{trackId}/stream",
                StringComparison.Ordinal));
        return (
            serviceProvider,
            endpoint.RequestDelegate ?? throw new InvalidOperationException("Stream route has no request delegate."));
    }

    private static async Task<DefaultHttpContext> InvokeStreamAsync(
        IServiceProvider services,
        RequestDelegate requestDelegate,
        string? token = null,
        string? range = null)
    {
        var context = new DefaultHttpContext
        {
            RequestServices = services
        };
        context.Request.Method = HttpMethods.Get;
        context.Request.Path = "/api/scan-sources/source-1/tracks/track-1/stream";
        context.Request.RouteValues["id"] = "source-1";
        context.Request.RouteValues["trackId"] = "track-1";
        if (token is not null) context.Request.Headers.Authorization = $"Bearer {token}";
        if (range is not null) context.Request.Headers.Range = range;
        context.Response.Body = new MemoryStream();

        await requestDelegate(context);
        return context;
    }

    private sealed class FakeAuthService : IAuthService
    {
        public AuthTokenResponse? SignIn(string username, string password) => null;

        public AuthTokenResponse? Refresh(string refreshToken) => null;

        public AccountResponse? Authenticate(string? accessToken) => accessToken switch
        {
            "alice-token" => new AccountResponse("alice-id", "alice", "Alice", null),
            "bob-token" => new AccountResponse("bob-id", "bob", "Bob", null),
            _ => null
        };

        public bool RevokeAll(string accessToken) => false;
    }

    private sealed class FakeMusicScanService : IMusicScanService
    {
        public int OpenCalls { get; private set; }
        public string? LastUsername { get; private set; }

        public ScannedTrackFile? OpenTrackFile(string username, string sourceId, string trackId)
        {
            OpenCalls++;
            LastUsername = username;
            if (username != "alice" || sourceId != "source-1" || trackId != "track-1") return null;
            return new ScannedTrackFile(
                new MemoryStream([10, 20, 30, 40], writable: false),
                "audio/mpeg",
                4,
                new DateTimeOffset(2026, 9, 9, 0, 0, 0, TimeSpan.Zero));
        }

        public IReadOnlyList<ScanSourceResponse> GetSources(string username) => [];

        public IReadOnlyList<ScannedTrackResponse> GetTracks(string username, string sourceId, int limit) => [];

        public ScanSourceResponse CreateSource(string username, CreateScanSourceRequest request) =>
            throw new NotSupportedException();

        public ScanSourceResponse? UpdateSource(string username, string id, UpdateScanSourceRequest request) =>
            throw new NotSupportedException();

        public bool DeleteSource(string username, string id) => throw new NotSupportedException();

        public Task<ScanSourceResponse?> ScanNowAsync(
            string username,
            string id,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task ScanDueAsync(CancellationToken cancellationToken) => throw new NotSupportedException();
    }

    private sealed class TestEndpointRouteBuilder(IServiceProvider serviceProvider) : IEndpointRouteBuilder
    {
        public IServiceProvider ServiceProvider { get; } = serviceProvider;
        public ICollection<EndpointDataSource> DataSources { get; } = [];

        public IApplicationBuilder CreateApplicationBuilder() =>
            new ApplicationBuilder(ServiceProvider);
    }
}
