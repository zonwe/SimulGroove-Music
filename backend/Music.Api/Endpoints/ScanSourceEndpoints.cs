using Music.Api.Data;
using Music.Api.Models;
using Music.Api.Services;
using Music.Api.Services.Scanning;

namespace Music.Api.Endpoints;

public static class ScanSourceEndpoints
{
    public static IEndpointRouteBuilder MapScanSourceEndpoints(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/scan-sources");

        group.MapGet("/", (HttpRequest request, IAuthService auth, IMusicScanService scanner) =>
        {
            var account = Authenticate(request, auth);
            return account is null ? Results.Unauthorized() : Results.Ok(scanner.GetSources(account.Username));
        });

        group.MapPost("/", (CreateScanSourceRequest body, HttpRequest request, IAuthService auth, IMusicScanService scanner, IAuditLogStore logs) =>
        {
            var account = Authenticate(request, auth);
            if (account is null) return Results.Unauthorized();
            try
            {
                var source = scanner.CreateSource(account.Username, body);
                logs.Record(new AuditLogEntry(account.Username, "information", "scan.source.created", $"Created scan source {source.Path}.", DateTimeOffset.UtcNow, Details: $"{{\"sourceId\":\"{source.Id}\"}}"));
                return Results.Created($"/api/scan-sources/{source.Id}", source);
            }
            catch (ArgumentException exception)
            {
                return Results.BadRequest(new ProblemResponse("invalid_scan_source", exception.Message));
            }
            catch (DuplicateScanSourceException)
            {
                return Results.Conflict(new ProblemResponse("duplicate_scan_source", "This path has already been configured."));
            }
        });

        group.MapPut("/{id}", (string id, UpdateScanSourceRequest body, HttpRequest request, IAuthService auth, IMusicScanService scanner, IAuditLogStore logs) =>
        {
            var account = Authenticate(request, auth);
            if (account is null) return Results.Unauthorized();
            try
            {
                var source = scanner.UpdateSource(account.Username, id, body);
                if (source is not null) logs.Record(new AuditLogEntry(account.Username, "information", "scan.source.updated", $"Updated scan source {source.Path}.", DateTimeOffset.UtcNow, Details: $"{{\"sourceId\":\"{source.Id}\"}}"));
                return source is null ? Results.NotFound() : Results.Ok(source);
            }
            catch (ArgumentException exception)
            {
                return Results.BadRequest(new ProblemResponse("invalid_scan_source", exception.Message));
            }
            catch (DuplicateScanSourceException)
            {
                return Results.Conflict(new ProblemResponse("duplicate_scan_source", "This path has already been configured."));
            }
        });

        group.MapDelete("/{id}", (string id, HttpRequest request, IAuthService auth, IAuditLogStore logs, IMusicScanService scanner) =>
        {
            var account = Authenticate(request, auth);
            if (account is null) return Results.Unauthorized();
            if (!scanner.DeleteSource(account.Username, id)) return Results.NotFound();
            logs.Record(new AuditLogEntry(account.Username, "information", "scan.source.deleted", $"Deleted scan source {id}.", DateTimeOffset.UtcNow));
            return Results.NoContent();
        });

        group.MapPost("/{id}/scan", async (string id, HttpRequest request, IAuthService auth, IMusicScanService scanner, IAuditLogStore logs, CancellationToken cancellationToken) =>
        {
            var account = Authenticate(request, auth);
            if (account is null) return Results.Unauthorized();
            var source = await scanner.ScanNowAsync(account.Username, id, cancellationToken);
            if (source is not null) logs.Record(new AuditLogEntry(account.Username, source.Status == "failed" ? "error" : "information", "scan.manual", $"Manual scan finished with status {source.Status}.", DateTimeOffset.UtcNow, Details: $"{{\"sourceId\":\"{source.Id}\",\"trackCount\":{source.TrackCount}}}"));
            return source is null ? Results.NotFound() : Results.Ok(source);
        });

        group.MapGet("/{id}/tracks", (string id, int? limit, HttpRequest request, IAuthService auth, IMusicScanService scanner) =>
        {
            var account = Authenticate(request, auth);
            return account is null
                ? Results.Unauthorized()
                : Results.Ok(scanner.GetTracks(account.Username, id, limit ?? 200));
        });

        group.MapGet("/{id}/tracks/{trackId}/stream", (
            string id,
            string trackId,
            HttpContext httpContext,
            IAuthService auth,
            IMusicScanService scanner) =>
        {
            var account = Authenticate(httpContext.Request, auth);
            if (account is null) return Results.Unauthorized();

            var track = scanner.GetTrackFile(account.Username, id, trackId);
            if (track is null)
            {
                return Results.Json(
                    new ProblemResponse("server_track_not_found", "The indexed track is unavailable."),
                    statusCode: StatusCodes.Status404NotFound);
            }

            httpContext.Response.Headers.CacheControl = "private, no-store";
            httpContext.Response.Headers["X-Content-Type-Options"] = "nosniff";
            return Results.File(
                track.FilePath,
                track.ContentType,
                lastModified: track.ModifiedAt,
                enableRangeProcessing: true);
        });

        return endpoints;
    }

    private static AccountResponse? Authenticate(HttpRequest request, IAuthService auth) =>
        auth.Authenticate(request.ReadBearerToken());
}
