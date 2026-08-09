using System.Net;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
public sealed class OnlineMusicSidecarHealthCheckTests
{
    [TestMethod]
    public async Task DisabledFeatureDoesNotRequireSidecar()
    {
        var check = CreateCheck(
            new ThrowingHttpMessageHandler(),
            new OnlineMusicOptions { Enabled = false });

        var result = await check.CheckHealthAsync(new HealthCheckContext());

        Assert.AreEqual(HealthStatus.Healthy, result.Status);
    }

    [TestMethod]
    public async Task EnabledFeatureProbesPrivateHealthEndpoint()
    {
        Uri? observedUri = null;
        var check = CreateCheck(
            new StubHttpMessageHandler(request =>
            {
                observedUri = request.RequestUri;
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));
            }),
            new OnlineMusicOptions
            {
                Enabled = true,
                SidecarBaseUrl = "http://127.0.0.1:8080/root/"
            });

        var result = await check.CheckHealthAsync(new HealthCheckContext());

        Assert.AreEqual(HealthStatus.Healthy, result.Status);
        Assert.AreEqual(
            "http://127.0.0.1:8080/root/integration/v1/health",
            observedUri?.ToString());
    }

    [TestMethod]
    public async Task UnreachableSidecarMakesReadinessUnhealthy()
    {
        var check = CreateCheck(
            new ThrowingHttpMessageHandler(),
            new OnlineMusicOptions
            {
                Enabled = true,
                SidecarBaseUrl = "http://127.0.0.1:8080"
            });

        var result = await check.CheckHealthAsync(new HealthCheckContext());

        Assert.AreEqual(HealthStatus.Unhealthy, result.Status);
        Assert.AreEqual("Online music sidecar is unreachable.", result.Description);
    }

    private static OnlineMusicSidecarHealthCheck CreateCheck(
        HttpMessageHandler handler,
        OnlineMusicOptions options) => new(
            new StubHttpClientFactory(new HttpClient(handler)),
            Options.Create(options));

    private sealed class StubHttpClientFactory(HttpClient client) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => client;
    }

    private sealed class StubHttpMessageHandler(
        Func<HttpRequestMessage, Task<HttpResponseMessage>> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => handler(request);
    }

    private sealed class ThrowingHttpMessageHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) =>
            throw new HttpRequestException("sensitive upstream details");
    }
}
