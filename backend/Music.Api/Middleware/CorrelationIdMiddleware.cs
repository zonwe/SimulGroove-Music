using System.Diagnostics;

namespace Music.Api.Middleware;

public sealed class CorrelationIdMiddleware(RequestDelegate next)
{
    public const string HeaderName = "X-Correlation-ID";
    public const int MaximumLength = 64;

    public async Task InvokeAsync(HttpContext context)
    {
        var correlationId = GetIncomingCorrelationId(context.Request) ??
            GetFallbackCorrelationId(context);
        context.TraceIdentifier = correlationId;
        context.Response.Headers[HeaderName] = correlationId;
        context.Response.OnStarting(() =>
        {
            context.Response.Headers[HeaderName] = correlationId;
            return Task.CompletedTask;
        });

        await next(context);
    }

    public static bool IsValid(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > MaximumLength)
        {
            return false;
        }

        return value.All(character =>
            char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.');
    }

    private static string? GetIncomingCorrelationId(HttpRequest request)
    {
        if (!request.Headers.TryGetValue(HeaderName, out var values) || values.Count != 1)
        {
            return null;
        }

        var value = values[0]?.Trim();
        return IsValid(value) ? value : null;
    }

    private static string GetFallbackCorrelationId(HttpContext context)
    {
        var activityTraceId = Activity.Current?.TraceId.ToString();
        if (IsValid(activityTraceId))
        {
            return activityTraceId!;
        }

        if (IsValid(context.TraceIdentifier))
        {
            return context.TraceIdentifier;
        }

        return Guid.NewGuid().ToString("N");
    }
}
