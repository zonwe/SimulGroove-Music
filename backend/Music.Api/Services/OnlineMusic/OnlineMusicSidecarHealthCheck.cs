using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;

namespace Music.Api.Services.OnlineMusic;

public sealed class OnlineMusicSidecarHealthCheck(
    IHttpClientFactory clientFactory,
    IOptions<OnlineMusicOptions> options) : IHealthCheck
{
    public const string HttpClientName = "online-music-sidecar-health";

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var settings = options.Value;
        if (!settings.Enabled)
        {
            return HealthCheckResult.Healthy("Online music is disabled.");
        }

        if (!TryCreateHealthUri(settings.SidecarBaseUrl, out var healthUri))
        {
            return HealthCheckResult.Unhealthy("Online music sidecar URL is invalid.");
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(
            Math.Clamp(settings.HealthCheckTimeoutSeconds, 1, 10)));

        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, healthUri);
            using var response = await clientFactory
                .CreateClient(HttpClientName)
                .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (!response.IsSuccessStatusCode)
            {
                return HealthCheckResult.Unhealthy(
                    $"Online music sidecar returned HTTP {(int)response.StatusCode}.");
            }

            return HealthCheckResult.Healthy("Online music sidecar is reachable.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return HealthCheckResult.Unhealthy("Online music sidecar health check timed out.");
        }
        catch (HttpRequestException)
        {
            return HealthCheckResult.Unhealthy("Online music sidecar is unreachable.");
        }
    }

    private static bool TryCreateHealthUri(string baseUrl, out Uri? healthUri)
    {
        healthUri = null;
        if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var baseAddress) ||
            (baseAddress.Scheme != Uri.UriSchemeHttp && baseAddress.Scheme != Uri.UriSchemeHttps))
        {
            return false;
        }

        healthUri = new Uri($"{baseAddress.ToString().TrimEnd('/')}/integration/v1/health");
        return true;
    }
}
