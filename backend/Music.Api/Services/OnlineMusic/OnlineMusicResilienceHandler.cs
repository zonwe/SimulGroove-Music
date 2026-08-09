using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Net;

namespace Music.Api.Services.OnlineMusic;

public sealed class OnlineMusicResilienceHandler(
    OnlineMusicCircuitBreaker circuitBreaker) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var operation = GetOperation(request.RequestUri?.AbsolutePath);
        OnlineMusicCircuitLease lease;
        try
        {
            lease = circuitBreaker.Enter();
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

    private static string GetOperation(string? path)
    {
        if (path is null) return "other";
        if (path.EndsWith("/search", StringComparison.Ordinal)) return "search";
        if (path.EndsWith("/resolve", StringComparison.Ordinal)) return "resolve";
        if (path.Contains("/streams/", StringComparison.Ordinal)) return "stream";
        if (path.EndsWith("/lyrics", StringComparison.Ordinal)) return "lyrics";
        if (path.EndsWith("/cover", StringComparison.Ordinal)) return "artwork";
        return "other";
    }

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
