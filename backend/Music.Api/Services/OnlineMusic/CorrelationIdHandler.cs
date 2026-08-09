using Music.Api.Middleware;

namespace Music.Api.Services.OnlineMusic;

public sealed class CorrelationIdHandler(IHttpContextAccessor contextAccessor) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        var correlationId = contextAccessor.HttpContext?.TraceIdentifier;
        if (CorrelationIdMiddleware.IsValid(correlationId) &&
            !request.Headers.Contains(CorrelationIdMiddleware.HeaderName))
        {
            request.Headers.TryAddWithoutValidation(
                CorrelationIdMiddleware.HeaderName,
                correlationId);
        }

        return base.SendAsync(request, cancellationToken);
    }
}
