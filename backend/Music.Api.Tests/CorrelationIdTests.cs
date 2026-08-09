using System.Net;
using Microsoft.AspNetCore.Http;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Middleware;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
public sealed class CorrelationIdTests
{
    [TestMethod]
    public async Task MiddlewareAcceptsSafeIncomingIdAndAddsResponseHeader()
    {
        var context = new DefaultHttpContext();
        context.Request.Headers[CorrelationIdMiddleware.HeaderName] = "request-123";
        string? observedTraceId = null;
        var middleware = new CorrelationIdMiddleware(nextContext =>
        {
            observedTraceId = nextContext.TraceIdentifier;
            return Task.CompletedTask;
        });

        await middleware.InvokeAsync(context);
        await context.Response.StartAsync();

        Assert.AreEqual("request-123", observedTraceId);
        Assert.AreEqual(
            "request-123",
            context.Response.Headers[CorrelationIdMiddleware.HeaderName].ToString());
    }

    [TestMethod]
    public async Task MiddlewareReplacesUnsafeIncomingId()
    {
        var context = new DefaultHttpContext();
        context.Request.Headers[CorrelationIdMiddleware.HeaderName] = "unsafe value with spaces";
        var middleware = new CorrelationIdMiddleware(_ => Task.CompletedTask);

        await middleware.InvokeAsync(context);

        Assert.IsTrue(CorrelationIdMiddleware.IsValid(context.TraceIdentifier));
        Assert.AreNotEqual("unsafe value with spaces", context.TraceIdentifier);
    }

    [TestMethod]
    public async Task HandlerForwardsCurrentTraceIdentifier()
    {
        string? observedCorrelationId = null;
        var context = new DefaultHttpContext { TraceIdentifier = "trace-456" };
        var handler = new CorrelationIdHandler(new HttpContextAccessor { HttpContext = context })
        {
            InnerHandler = new StubHttpMessageHandler(request =>
            {
                observedCorrelationId = request.Headers
                    .GetValues(CorrelationIdMiddleware.HeaderName)
                    .Single();
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));
            })
        };
        using var client = new HttpClient(handler);

        using var response = await client.GetAsync("http://127.0.0.1/health");

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        Assert.AreEqual("trace-456", observedCorrelationId);
    }

    private sealed class StubHttpMessageHandler(
        Func<HttpRequestMessage, Task<HttpResponseMessage>> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => handler(request);
    }
}
