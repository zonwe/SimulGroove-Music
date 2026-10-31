using System.Net;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Middleware;

namespace Music.Api.Tests;

/// <summary>
/// 转发头是限流配额与审计日志的真实 IP 来源，也是唯一可能被客户端伪造的边界：
/// 默认必须只信任回环代理，并且永远不采信 X-Forwarded-Host。
/// </summary>
[TestClass]
public sealed class ForwardedHeadersTests
{
    [TestMethod]
    public void DefaultOptionsOnlyForwardForAndProto()
    {
        var options = ForwardedHeadersSetup.CreateOptions(BuildConfiguration(false));

        Assert.AreEqual(
            ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
            options.ForwardedHeaders);
        // 默认信任范围只包含回环地址：任何非回环来源都不能改写客户端 IP。
        Assert.IsTrue(
            options.KnownProxies.All(IPAddress.IsLoopback),
            "默认只允许回环代理，否则任意来源都能伪造客户端 IP。");
        Assert.IsTrue(
            options.KnownIPNetworks.Count > 0,
            "默认必须保留回环信任范围，否则任意来源都能伪造客户端 IP。");
    }

    [TestMethod]
    public void TrustNonLoopbackProxyClearsLoopbackRestriction()
    {
        var options = ForwardedHeadersSetup.CreateOptions(BuildConfiguration(true));

        Assert.AreEqual(0, options.KnownProxies.Count);
        Assert.AreEqual(0, options.KnownIPNetworks.Count);
    }

    [TestMethod]
    public async Task ForwardedHeadersFromNonLoopbackAreIgnoredByDefault()
    {
        var context = CreateContext(IPAddress.Parse("203.0.113.10"));
        context.Request.Headers["X-Forwarded-For"] = "198.51.100.7";
        context.Request.Headers["X-Forwarded-Proto"] = "https";

        await InvokeAsync(
            context,
            ForwardedHeadersSetup.CreateOptions(BuildConfiguration(false)));

        Assert.AreEqual(
            IPAddress.Parse("203.0.113.10"),
            context.Connection.RemoteIpAddress);
        Assert.AreEqual("http", context.Request.Scheme);
    }

    [TestMethod]
    public async Task LoopbackProxyIsTrustedButHostHeaderIsNot()
    {
        var context = CreateContext(IPAddress.Loopback);
        context.Request.Headers["X-Forwarded-For"] = "198.51.100.7";
        context.Request.Headers["X-Forwarded-Proto"] = "https";
        context.Request.Headers["X-Forwarded-Host"] = "evil.example.com";

        await InvokeAsync(
            context,
            ForwardedHeadersSetup.CreateOptions(BuildConfiguration(false)));

        Assert.AreEqual(
            IPAddress.Parse("198.51.100.7"),
            context.Connection.RemoteIpAddress);
        Assert.AreEqual("https", context.Request.Scheme);
        Assert.AreEqual(
            "localhost",
            context.Request.Host.Host,
            "主机头必须由 AllowedHosts 校验，不能被转发头改写。");
    }

    [TestMethod]
    public async Task ExplicitTrustAllowsPrivateBridgeProxy()
    {
        var context = CreateContext(IPAddress.Parse("172.18.0.5"));
        context.Request.Headers["X-Forwarded-For"] = "198.51.100.7";
        context.Request.Headers["X-Forwarded-Proto"] = "https";

        await InvokeAsync(
            context,
            ForwardedHeadersSetup.CreateOptions(BuildConfiguration(true)));

        Assert.AreEqual(
            IPAddress.Parse("198.51.100.7"),
            context.Connection.RemoteIpAddress);
        Assert.AreEqual("https", context.Request.Scheme);
    }

    private static IConfiguration BuildConfiguration(bool trustNonLoopbackProxy) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                [ForwardedHeadersSetup.TrustNonLoopbackProxyKey] =
                    trustNonLoopbackProxy ? "true" : "false",
            })
            .Build();

    private static DefaultHttpContext CreateContext(IPAddress remoteAddress)
    {
        var context = new DefaultHttpContext();
        context.Connection.RemoteIpAddress = remoteAddress;
        context.Request.Scheme = "http";
        context.Request.Host = new HostString("localhost", 5080);
        return context;
    }

    private static async Task InvokeAsync(
        HttpContext context,
        ForwardedHeadersOptions options)
    {
        var middleware = new ForwardedHeadersMiddleware(
            static _ => Task.CompletedTask,
            NullLoggerFactory.Instance,
            Options.Create(options));
        await middleware.Invoke(context);
    }
}
