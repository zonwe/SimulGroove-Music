using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.HttpOverrides;

namespace Music.Api.Middleware;

/// <summary>
/// 反向代理转发头配置。
///
/// 默认只信任回环代理（同机 Nginx），公网直接发来的 X-Forwarded-For 会被忽略；
/// 容器编排里入口代理位于私有桥接网段，需要 ForwardedHeaders:TrustNonLoopbackProxy=true
/// 显式放开，且只有在网络边界保证外部无法直达 API 时才可开启。
///
/// 只接受 For/Proto：主机校验由 AllowedHosts 负责，不能信任客户端可伪造的
/// X-Forwarded-Host。不要把这里换成 ASPNETCORE_FORWARDEDHEADERS_ENABLED——它使用
/// 默认选项注册中间件、接受任意来源的 X-Forwarded-For，并与显式配置重复。
/// </summary>
public static class ForwardedHeadersSetup
{
    public const string TrustNonLoopbackProxyKey =
        "ForwardedHeaders:TrustNonLoopbackProxy";

    public static ForwardedHeadersOptions CreateOptions(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var options = new ForwardedHeadersOptions
        {
            ForwardedHeaders = ForwardedHeaders.XForwardedFor |
                ForwardedHeaders.XForwardedProto
        };

        if (configuration.GetValue<bool>(TrustNonLoopbackProxyKey))
        {
            options.KnownIPNetworks.Clear();
            options.KnownProxies.Clear();
        }

        return options;
    }
}
