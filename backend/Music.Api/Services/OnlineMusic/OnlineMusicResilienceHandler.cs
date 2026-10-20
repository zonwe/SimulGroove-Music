using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Net;

namespace Music.Api.Services.OnlineMusic;

/// <summary>
/// 为 sidecar 调用提供按操作隔离的熔断。
///
/// 只有瞬时故障（网络错误、超时、HTTP 408/429/5xx）才计入失败；404、422 等稳定业务
/// 结果不计入，否则"这首歌没有封面"会把熔断器打开并连坐其他操作。
/// </summary>
public sealed class OnlineMusicResilienceHandler(
    OnlineMusicCircuitBreaker circuitBreaker) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var operation = OnlineMusicOperations.FromPath(request.RequestUri?.AbsolutePath);
        OnlineMusicCircuitLease lease;
        try
        {
            lease = circuitBreaker.Enter(operation);
        }
        catch (OnlineMusicCircuitOpenException)
        {
            OnlineMusicTelemetry.CircuitRejections.Add(1, OperationTag(operation));
            throw;
        }

        var stopwatch = Stopwatch.StartNew();
        OnlineMusicTelemetry.SidecarRequests.Add(1, OperationTag(operation));
        try
        {
            var response = await base.SendAsync(request, cancellationToken);
            if (IsTransientFailure(response.StatusCode))
            {
                circuitBreaker.RecordFailure(lease);
                RecordFailure(operation, "http");
            }
            else
            {
                circuitBreaker.RecordSuccess(lease);
            }

            return response;
        }
        catch (HttpRequestException)
        {
            circuitBreaker.RecordFailure(lease);
            RecordFailure(operation, "network");
            throw;
        }
        catch (OperationCanceledException exception)
            when (exception.InnerException is TimeoutException)
        {
            circuitBreaker.RecordFailure(lease);
            RecordFailure(operation, "timeout");
            throw;
        }
        catch
        {
            circuitBreaker.Release(lease);
            throw;
        }
        finally
        {
            stopwatch.Stop();
            OnlineMusicTelemetry.SidecarDuration.Record(
                stopwatch.Elapsed.TotalMilliseconds,
                OperationTag(operation));
        }
    }

    private static bool IsTransientFailure(HttpStatusCode statusCode) =>
        statusCode is HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests ||
        (int)statusCode >= 500;

    private static KeyValuePair<string, object?> OperationTag(string operation) =>
        new("operation", operation);

    private static void RecordFailure(string operation, string failureType)
    {
        TagList tags = default;
        tags.Add("operation", operation);
        tags.Add("failure.type", failureType);
        OnlineMusicTelemetry.SidecarFailures.Add(1, tags);
    }
}
