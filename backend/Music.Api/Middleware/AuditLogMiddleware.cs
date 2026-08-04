using System.Diagnostics;
using System.Text.Json;
using Music.Api.Data;
using Music.Api.Endpoints;
using Music.Api.Services;

namespace Music.Api.Middleware;

public sealed class AuditLogMiddleware(RequestDelegate next, ILogger<AuditLogMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context, IAuditLogStore logs, IAuthService auth)
    {
        if (!context.Request.Path.StartsWithSegments("/api"))
        {
            await next(context);
            return;
        }

        var stopwatch = Stopwatch.StartNew();
        var requestFailed = false;
        try
        {
            await next(context);
        }
        catch
        {
            requestFailed = true;
            throw;
        }
        finally
        {
            stopwatch.Stop();
            var account = auth.Authenticate(context.Request.ReadBearerToken());
            if (account is not null)
            {
                var status = requestFailed ? StatusCodes.Status500InternalServerError : context.Response.StatusCode;
                var level = status >= 500 ? "error" : status >= 400 ? "warning" : "information";
                try
                {
                    logs.Record(new Models.AuditLogEntry(
                        account.Username,
                        level,
                        "http.request",
                        $"{context.Request.Method} {context.Request.Path} returned {status}.",
                        DateTimeOffset.UtcNow,
                        context.Request.Method,
                        context.Request.Path.Value,
                        status,
                        (int)stopwatch.ElapsedMilliseconds,
                        context.Connection.RemoteIpAddress?.ToString(),
                        context.TraceIdentifier,
                        JsonSerializer.Serialize(new { query = context.Request.QueryString.Value })));
                }
                catch (Exception exception)
                {
                    logger.LogError(exception, "Unable to persist audit log for {Path}.", context.Request.Path);
                }
            }
        }
    }
}
