namespace Music.Api.Endpoints;

public static class RequestAuthentication
{
    public static string? ReadBearerToken(this HttpRequest request)
    {
        if (request.Headers.TryGetValue("Authorization", out var authorization))
        {
            const string prefix = "Bearer ";
            var value = authorization.ToString();
            if (value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return value[prefix.Length..].Trim();
            }
        }

        return request.Headers.TryGetValue("X-Session-Token", out var header)
            ? header.ToString().Trim()
            : null;
    }
}
