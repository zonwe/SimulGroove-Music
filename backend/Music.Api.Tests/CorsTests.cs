using Microsoft.AspNetCore.Cors.Infrastructure;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Music.Api.Tests;

[TestClass]
public sealed class CorsTests
{
    [TestMethod]
    public async Task DefaultCorsPolicyAllowsAnyOriginWithCredentialsAndExposesHeaders()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddCors(options =>
            options.AddDefaultPolicy(policy =>
                policy
                    .SetIsOriginAllowed(_ => true)
                    .AllowAnyHeader()
                    .AllowAnyMethod()
                    .AllowCredentials()
                    .WithExposedHeaders("*")));

        using var serviceProvider = services.BuildServiceProvider();
        var policyProvider = serviceProvider.GetRequiredService<ICorsPolicyProvider>();
        var corsService = serviceProvider.GetRequiredService<ICorsService>();

        var httpContext = new DefaultHttpContext();
        httpContext.Request.Headers.Origin = "http://localhost:5173";
        httpContext.Request.Headers["Access-Control-Request-Method"] = "POST";
        httpContext.Request.Headers["Access-Control-Request-Headers"] = "authorization,content-type,x-correlation-id";

        var policy = await policyProvider.GetPolicyAsync(httpContext, null);
        Assert.IsNotNull(policy);
        Assert.IsTrue(policy.SupportsCredentials);
        Assert.IsTrue(policy.AllowAnyHeader);
        Assert.IsTrue(policy.AllowAnyMethod);
        Assert.IsTrue(policy.IsOriginAllowed("http://localhost:5173"));
        Assert.IsTrue(policy.IsOriginAllowed("http://192.168.1.100:8080"));
        Assert.IsTrue(policy.IsOriginAllowed("https://music.example.com"));
        Assert.IsTrue(policy.ExposedHeaders.Contains("*"));

        var result = corsService.EvaluatePolicy(httpContext, policy);
        Assert.IsTrue(result.IsOriginAllowed);
        Assert.IsTrue(result.SupportsCredentials);

        corsService.ApplyResult(result, httpContext.Response);
        Assert.AreEqual("http://localhost:5173", httpContext.Response.Headers.AccessControlAllowOrigin.ToString());
        Assert.AreEqual("true", httpContext.Response.Headers.AccessControlAllowCredentials.ToString());
    }

    [TestMethod]
    public async Task PreflightOptionsEvaluationAllowsMethodsAndHeaders()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddCors(options =>
            options.AddDefaultPolicy(policy =>
                policy
                    .SetIsOriginAllowed(_ => true)
                    .AllowAnyHeader()
                    .AllowAnyMethod()
                    .AllowCredentials()
                    .WithExposedHeaders("*")));

        using var serviceProvider = services.BuildServiceProvider();
        var policyProvider = serviceProvider.GetRequiredService<ICorsPolicyProvider>();
        var corsService = serviceProvider.GetRequiredService<ICorsService>();

        var httpContext = new DefaultHttpContext();
        httpContext.Request.Method = HttpMethods.Options;
        httpContext.Request.Headers.Origin = "http://127.0.0.1:3000";
        httpContext.Request.Headers["Access-Control-Request-Method"] = "PUT";
        httpContext.Request.Headers["Access-Control-Request-Headers"] = "authorization,x-custom-header";

        var policy = await policyProvider.GetPolicyAsync(httpContext, null);
        Assert.IsNotNull(policy);

        var result = corsService.EvaluatePolicy(httpContext, policy);
        Assert.IsTrue(result.IsOriginAllowed);
        Assert.IsTrue(result.IsPreflightRequest);
        Assert.IsTrue(result.SupportsCredentials);

        corsService.ApplyResult(result, httpContext.Response);
        Assert.AreEqual("http://127.0.0.1:3000", httpContext.Response.Headers.AccessControlAllowOrigin.ToString());
        Assert.AreEqual("true", httpContext.Response.Headers.AccessControlAllowCredentials.ToString());
        Assert.IsTrue(httpContext.Response.Headers.AccessControlAllowMethods.ToString().Contains("PUT"));
    }
}
