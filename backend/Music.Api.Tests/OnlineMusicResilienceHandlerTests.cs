using System.Diagnostics.Metrics;
using System.Net;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
[DoNotParallelize]
public sealed class OnlineMusicResilienceHandlerTests
{
    [TestMethod]
    public async Task ConsecutiveTransientFailuresOpenCircuitAndSuccessfulProbeClosesIt()
    {
        var clock = new MutableTimeProvider(new DateTimeOffset(2026, 8, 8, 0, 0, 0, TimeSpan.Zero));
        var breaker = CreateCircuitBreaker(clock, failureThreshold: 2, breakSeconds: 5);
        var responses = new Queue<HttpStatusCode>(
        [
            HttpStatusCode.ServiceUnavailable,
            HttpStatusCode.BadGateway,
            HttpStatusCode.OK,
            HttpStatusCode.OK
        ]);
        var innerCalls = 0;
        using var client = CreateClient(breaker, _ =>
        {
            innerCalls++;
            return Task.FromResult(new HttpResponseMessage(responses.Dequeue()));
        });

        using (var first = await client.GetAsync("integration/v1/search"))
        {
            Assert.AreEqual(HttpStatusCode.ServiceUnavailable, first.StatusCode);
        }
        using (var second = await client.GetAsync("integration/v1/search"))
        {
            Assert.AreEqual(HttpStatusCode.BadGateway, second.StatusCode);
        }

        await Assert.ThrowsAsync<OnlineMusicCircuitOpenException>(() =>
            client.GetAsync("integration/v1/search"));
        Assert.AreEqual(2, innerCalls);

        clock.Advance(TimeSpan.FromSeconds(5));
        using (var recoveryProbe = await client.GetAsync("integration/v1/search"))
        {
            Assert.AreEqual(HttpStatusCode.OK, recoveryProbe.StatusCode);
        }
        using (var afterRecovery = await client.GetAsync("integration/v1/search"))
        {
            Assert.AreEqual(HttpStatusCode.OK, afterRecovery.StatusCode);
        }
        Assert.AreEqual(4, innerCalls);
    }

    [TestMethod]
    public async Task StableClientErrorsDoNotOpenCircuit()
    {
        var breaker = CreateCircuitBreaker(
            new MutableTimeProvider(DateTimeOffset.UtcNow),
            failureThreshold: 2,
            breakSeconds: 5);
        var innerCalls = 0;
        using var client = CreateClient(breaker, _ =>
        {
            innerCalls++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
        });

        for (var index = 0; index < 4; index++)
        {
            using var response = await client.GetAsync("integration/v1/tracks/source/track/cover");
            Assert.AreEqual(HttpStatusCode.NotFound, response.StatusCode);
        }

        Assert.AreEqual(4, innerCalls);
    }

    [TestMethod]
    public async Task StableUnprocessableBusinessResultsDoNotOpenCircuit()
    {
        // sidecar 用 422 表达"这首歌没有封面/没有可播放音源"这类稳定结果。
        // 它必须被当作正常业务响应，否则一次批量封面失败就会连坐搜索。
        var breaker = CreateCircuitBreaker(
            new MutableTimeProvider(DateTimeOffset.UtcNow),
            failureThreshold: 2,
            breakSeconds: 5);
        var innerCalls = 0;
        using var client = CreateClient(breaker, _ =>
        {
            innerCalls++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.UnprocessableEntity));
        });

        for (var index = 0; index < 6; index++)
        {
            using var response = await client.GetAsync("integration/v1/tracks/source/track/cover");
            Assert.AreEqual(HttpStatusCode.UnprocessableEntity, response.StatusCode);
        }

        Assert.AreEqual(6, innerCalls, "422 must never trip the circuit");
    }

    [TestMethod]
    public async Task ArtworkFailuresDoNotOpenTheSearchCircuit()
    {
        // 回归：封面连续 5xx 曾经打开全局熔断，导致紧接着的搜索返回"服务不可用"。
        var clock = new MutableTimeProvider(new DateTimeOffset(2026, 8, 8, 0, 0, 0, TimeSpan.Zero));
        var breaker = CreateCircuitBreaker(clock, failureThreshold: 5, breakSeconds: 30);
        using var client = CreateClient(breaker, _ => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.BadGateway)));

        for (var index = 0; index < 5; index++)
        {
            using var cover = await client.GetAsync("integration/v1/tracks/source/track/cover");
            Assert.AreEqual(HttpStatusCode.BadGateway, cover.StatusCode);
        }

        // artwork 熔断已经打开……
        await Assert.ThrowsAsync<OnlineMusicCircuitOpenException>(() =>
            client.GetAsync("integration/v1/tracks/source/track/cover"));

        // ……但搜索是独立操作，必须仍然可用。
        using var search = await client.GetAsync("integration/v1/search");
        Assert.AreEqual(HttpStatusCode.BadGateway, search.StatusCode);
    }

    [TestMethod]
    public async Task SearchFailuresDoNotOpenTheArtworkCircuit()
    {
        var clock = new MutableTimeProvider(new DateTimeOffset(2026, 8, 8, 0, 0, 0, TimeSpan.Zero));
        var breaker = CreateCircuitBreaker(clock, failureThreshold: 5, breakSeconds: 30);
        using var client = CreateClient(breaker, _ => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.BadGateway)));

        for (var index = 0; index < 5; index++)
        {
            using var search = await client.GetAsync("integration/v1/search");
            Assert.AreEqual(HttpStatusCode.BadGateway, search.StatusCode);
        }

        await Assert.ThrowsAsync<OnlineMusicCircuitOpenException>(() =>
            client.GetAsync("integration/v1/search"));

        using var cover = await client.GetAsync("integration/v1/tracks/source/track/cover");
        Assert.AreEqual(HttpStatusCode.BadGateway, cover.StatusCode);
    }

    [TestMethod]
    public async Task MetricsUseNormalizedOperationInsteadOfTrackIdentity()
    {
        var measurements = new List<KeyValuePair<string, object?>[]>();
        using var listener = new MeterListener
        {
            InstrumentPublished = (instrument, meterListener) =>
            {
                if (instrument.Meter.Name == OnlineMusicTelemetry.MeterName &&
                    instrument.Name == "flutter_music.online_music.sidecar.requests")
                {
                    meterListener.EnableMeasurementEvents(instrument);
                }
            }
        };
        listener.SetMeasurementEventCallback<long>((_, _, tags, _) =>
            measurements.Add(tags.ToArray()));
        listener.Start();

        var breaker = CreateCircuitBreaker(
            new MutableTimeProvider(DateTimeOffset.UtcNow),
            failureThreshold: 2,
            breakSeconds: 5);
        using var client = CreateClient(breaker, _ => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.OK)));

        using var response = await client.GetAsync(
            "integration/v1/tracks/private-source/private-track/lyrics");

        var tags = measurements.Single();
        Assert.AreEqual("lyrics", tags.Single(tag => tag.Key == "operation").Value);
        Assert.IsFalse(tags.Any(tag => tag.Value?.ToString()?.Contains("private", StringComparison.Ordinal) == true));
    }

    private static OnlineMusicCircuitBreaker CreateCircuitBreaker(
        TimeProvider timeProvider,
        int failureThreshold,
        int breakSeconds) => new(
            Options.Create(new OnlineMusicOptions
            {
                CircuitBreakerFailureThreshold = failureThreshold,
                CircuitBreakerBreakSeconds = breakSeconds
            }),
            NullLogger<OnlineMusicCircuitBreaker>.Instance,
            timeProvider);

    private static HttpClient CreateClient(
        OnlineMusicCircuitBreaker breaker,
        Func<HttpRequestMessage, Task<HttpResponseMessage>> innerHandler)
    {
        var handler = new OnlineMusicResilienceHandler(breaker)
        {
            InnerHandler = new StubHttpMessageHandler(innerHandler)
        };
        return new HttpClient(handler)
        {
            BaseAddress = new Uri("http://127.0.0.1:8080/")
        };
    }

    private sealed class StubHttpMessageHandler(
        Func<HttpRequestMessage, Task<HttpResponseMessage>> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => handler(request);
    }

    private sealed class MutableTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset _utcNow = utcNow;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public void Advance(TimeSpan duration) => _utcNow += duration;
    }
}
