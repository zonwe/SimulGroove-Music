using Music.Api.Data;
using Music.Api.Models;
using Music.Api.Services;

namespace Music.Api.Endpoints;

public static class AuthEndpoints
{
    public static IEndpointRouteBuilder MapAuthEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/api/auth/login", (LoginRequest request, IAuthService auth, IAuditLogStore logs) =>
        {
            var username = request.Username?.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrEmpty(request.Password))
            {
                logs.Record(new AuditLogEntry(username, "warning", "auth.login.failed", "Login request was missing username or password.", DateTimeOffset.UtcNow));
                return Results.BadRequest(new ProblemResponse("invalid_request", "username and password are required."));
            }

            var response = auth.SignIn(request.Username, request.Password);
            if (response is null)
            {
                logs.Record(new AuditLogEntry(username, "warning", "auth.login.failed", "Invalid username or password.", DateTimeOffset.UtcNow));
                return Results.Json(new ProblemResponse("invalid_credentials", "Invalid username or password."), statusCode: StatusCodes.Status401Unauthorized);
            }

            logs.Record(new AuditLogEntry(response.Account.Username, "information", "auth.login.succeeded", "Account signed in.", DateTimeOffset.UtcNow));
            return Results.Ok(response);
        });

        endpoints.MapPost("/api/auth/refresh", (RefreshTokenRequest request, IAuthService auth, IAuditLogStore logs) =>
        {
            if (string.IsNullOrWhiteSpace(request.RefreshToken))
            {
                return Results.BadRequest(new ProblemResponse("invalid_request", "refreshToken is required."));
            }

            var response = auth.Refresh(request.RefreshToken);
            if (response is not null)
            {
                logs.Record(new AuditLogEntry(response.Account.Username, "information", "auth.token.refreshed", "Access token refreshed.", DateTimeOffset.UtcNow));
            }
            return response is null
                ? Results.Json(new ProblemResponse("invalid_refresh_token", "Refresh token is invalid, expired, or revoked."), statusCode: StatusCodes.Status401Unauthorized)
                : Results.Ok(response);
        });

        endpoints.MapGet("/api/auth/me", (HttpRequest request, IAuthService auth) =>
        {
            var account = auth.Authenticate(request.ReadBearerToken());
            return account is null
                ? Results.Unauthorized()
                : Results.Ok(new SessionAccountResponse(account));
        });

        endpoints.MapPost("/api/auth/logout", (HttpRequest request, IAuthService auth, IAuditLogStore logs) =>
        {
            var token = request.ReadBearerToken();
            var account = auth.Authenticate(token);
            if (token is null || account is null || !auth.RevokeAll(token)) return Results.Unauthorized();
            logs.Record(new AuditLogEntry(account.Username, "information", "auth.logout", "Account signed out.", DateTimeOffset.UtcNow));
            return Results.NoContent();
        });

        return endpoints;
    }
}
