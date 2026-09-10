using Microsoft.AspNetCore.Cors.Infrastructure;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Services;

namespace Music.Api.Tests;

[TestClass]
public sealed class CorsTests
{
    [TestMethod]
    public void ConfiguredAllowedOriginsAreAcceptedAndOthersAreRejected()
    {
        var policy = BuildPolicy("https://music.example.com");

        Assert.IsTrue(policy.IsOriginAllowed("https://music.example.com"));
        Assert.IsFalse(policy.IsOriginAllowed("http://localhost:5173"));
        Assert.IsFalse(policy.IsOriginAllowed("https://evil.example.com"));
    }

    [TestMethod]
    public void UnconfiguredOriginsOnlyAllowLoopbackDevelopmentServers()
    {
        var policy = BuildPolicy();

        Assert.IsTrue(policy.IsOriginAllowed("http://localhost:5173"));
        Assert.IsTrue(policy.IsOriginAllowed("https://127.0.0.1:8080"));
        Assert.IsTrue(policy.IsOriginAllowed("http://[::1]:3000"));

        Assert.IsFalse(policy.IsOriginAllowed("https://music.example.com"));
        Assert.IsFalse(policy.IsOriginAllowed("http://192.168.1.100:8080"));
        Assert.IsFalse(policy.IsOriginAllowed("not-a-uri"));
        Assert.IsFalse(policy.IsOriginAllowed(""));
    }

    [TestMethod]
    public async Task AllowedOriginReceivesCredentialsAndExposedHeaders()
    {
        var (corsService, policyProvider) = CreateService();

        var httpContext = new DefaultHttpContext();
        httpContext.Request.Headers.Origin = "http://localhost:5173";
        httpContext.Request.Headers["Access-Control-Request-Method"] = "POST";
        httpContext.Request.Headers["Access-Control-Request-Headers"] =
            "authorization,content-type,x-correlation-id";

        var policy = await policyProvider.GetPolicyAsync(httpContext, null);
        Assert.IsNotNull(policy);

        var result = corsService.EvaluatePolicy(httpContext, policy);
        Assert.IsTrue(result.IsOriginAllowed);
        Assert.IsTrue(result.SupportsCredentials);

        corsService.ApplyResult(result, httpContext.Response);
        Assert.AreEqual(
            "http://localhost:5173",
            httpContext.Response.Headers.AccessControlAllowOrigin.ToString());
        Assert.AreEqual(
            "true",
            httpContext.Response.Headers.AccessControlAllowCredentials.ToString());
        Assert.IsTrue(
            httpContext.Response.Headers.AccessControlExposeHeaders.ToString()
                .Contains("x-correlation-id"));
    }

    [TestMethod]
    public async Task PreflightForAllowedOriginExposesMethodsAndHeaders()
    {
        var (corsService, policyProvider) = CreateService();

        var httpContext = new DefaultHttpContext();
        httpContext.Request.Method = HttpMethods.Options;
        httpContext.Request.Headers.Origin = "http://localhost:5173";
        httpContext.Request.Headers["Access-Control-Request-Method"] = "PUT";
        httpContext.Request.Headers["Access-Control-Request-Headers"] =
            "authorization,x-custom-header";

        var policy = await policyProvider.GetPolicyAsync(httpContext, null);
        Assert.IsNotNull(policy);

        var result = corsService.EvaluatePolicy(httpContext, policy);
        Assert.IsTrue(result.IsOriginAllowed);
        Assert.IsTrue(result.IsPreflightRequest);
        Assert.IsTrue(result.SupportsCredentials);

        corsService.ApplyResult(result, httpContext.Response);
        Assert.AreEqual(
            "http://localhost:5173",
            httpContext.Response.Headers.AccessControlAllowOrigin.ToString());
        Assert.AreEqual(
            "true",
            httpContext.Response.Headers.AccessControlAllowCredentials.ToString());
        Assert.IsTrue(
            httpContext.Response.Headers.AccessControlAllowMethods.ToString().Contains("PUT"));
    }

    [TestMethod]
    public void GetAllowedOriginsNormalizesTrailingSlashesAndIgnoresEmptyValues()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Cors:AllowedOrigins:0"] = "https://music.example.com/",
                ["Cors:AllowedOrigins:1"] = "",
                ["Cors:AllowedOrigins:2"] = "https://music.example.com",
            })
            .Build();

        var origins = CorsOriginPolicy.GetAllowedOrigins(configuration);

        CollectionAssert.AreEqual(
            new[] { "https://music.example.com" },
            origins.ToArray());
    }

    private static CorsPolicy BuildPolicy(params string[] allowedOrigins)
    {
        var (_, policyProvider) = CreateService(allowedOrigins);
        return policyProvider.GetPolicyAsync(new DefaultHttpContext(), null)
            .GetAwaiter().GetResult()
            ?? throw new InvalidOperationException("默认 CORS 策略未注册。");
    }

    private static (CorsService CorsService, ICorsPolicyProvider PolicyProvider) CreateService(
        params string[] allowedOrigins)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddCors(options =>
            options.AddDefaultPolicy(policyBuilder =>
                CorsOriginPolicy.Configure(policyBuilder, allowedOrigins)));

        var serviceProvider = services.BuildServiceProvider();
        return (
            (CorsService)serviceProvider.GetRequiredService<ICorsService>(),
            serviceProvider.GetRequiredService<ICorsPolicyProvider>());
    }
}
