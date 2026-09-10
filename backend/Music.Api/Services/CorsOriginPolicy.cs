using Microsoft.AspNetCore.Cors.Infrastructure;

namespace Music.Api.Services;

/// <summary>
/// 构建 API 的默认 CORS 策略。
///
/// 历史实现放行任意来源并允许携带凭据，使管理员 Cookie 的 CSRF 防护失效。
/// 现在的来源白名单来自 <c>Cors:AllowedOrigins</c> 配置；未配置时仅放行本机
/// 回环地址的 http(s) 来源，覆盖 Flutter Web 开发服务器（任意端口）。
/// </summary>
public static class CorsOriginPolicy
{
    /// <summary>允许凭据的请求中，浏览器只接受显式列出的可读响应头。</summary>
    public const string ExposedHeaders = "x-correlation-id";

    private static readonly HashSet<string> LoopbackHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "localhost",
        "127.0.0.1",
        "[::1]",
    };

    public static IReadOnlyList<string> GetAllowedOrigins(IConfiguration configuration)
    {
        var configured = configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
            ?? [];
        return configured
            .Select(NormalizeOrigin)
            .Where(origin => origin.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public static void Configure(CorsPolicyBuilder policy, IReadOnlyList<string> allowedOrigins)
    {
        policy
            .SetIsOriginAllowed(origin => IsOriginAllowed(origin, allowedOrigins))
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials()
            .WithExposedHeaders(ExposedHeaders);
    }

    public static bool IsOriginAllowed(string origin, IReadOnlyList<string> allowedOrigins)
    {
        if (!Uri.TryCreate(origin, UriKind.Absolute, out var parsed)
            || (parsed.Scheme != "http" && parsed.Scheme != "https"))
        {
            return false;
        }

        if (allowedOrigins.Count > 0)
        {
            return allowedOrigins.Contains(
                NormalizeOrigin(origin),
                StringComparer.OrdinalIgnoreCase);
        }

        // 未显式配置白名单时，只信任浏览器本机开发来源。
        return LoopbackHosts.Contains(parsed.Host);
    }

    private static string NormalizeOrigin(string origin) =>
        origin.Trim().TrimEnd('/');
}
