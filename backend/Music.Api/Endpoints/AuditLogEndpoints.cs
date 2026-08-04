using Music.Api.Data;
using Music.Api.Services;

namespace Music.Api.Endpoints;

public static class AuditLogEndpoints
{
    public static IEndpointRouteBuilder MapAuditLogEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/audit-logs", (
            HttpRequest request,
            IAuthService auth,
            IAuditLogStore logs,
            string? level,
            string? eventType,
            string? search,
            DateTimeOffset? from,
            DateTimeOffset? to,
            int? page,
            int? pageSize) =>
        {
            var account = auth.Authenticate(request.ReadBearerToken());
            return account is null
                ? Results.Unauthorized()
                : Results.Ok(logs.Query(account.Username, level, eventType, search, from, to, page ?? 1, pageSize ?? 50));
        });

        return endpoints;
    }
}
