using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.HttpOverrides;
using Music.Api.Data;
using Music.Api.Endpoints;
using Music.Api.Middleware;
using Music.Api.OpenApi;
using Music.Api.Services;
using Music.Api.Services.Administration;
using Music.Api.Services.OnlineMusic;
using Music.Api.Services.Scanning;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;

var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
{
	options.SerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
	options.SerializerOptions.PropertyNameCaseInsensitive = true;
	options.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.Never;
});
builder.Services.Configure<AdministrationOptions>(
	builder.Configuration.GetSection(AdministrationOptions.SectionName));
builder.Services.Configure<OnlineMusicOptions>(
	builder.Configuration.GetSection(OnlineMusicOptions.SectionName));

var otlpEndpointValue = builder.Configuration["Observability:OtlpEndpoint"];
if (!string.IsNullOrWhiteSpace(otlpEndpointValue))
{
	if (!Uri.TryCreate(otlpEndpointValue, UriKind.Absolute, out var otlpEndpoint) ||
		otlpEndpoint.Scheme is not ("http" or "https"))
	{
		throw new InvalidOperationException(
			"Observability:OtlpEndpoint must be an absolute HTTP or HTTPS URI.");
	}

	var observabilityServiceName =
		builder.Configuration["Observability:ServiceName"]?.Trim();
	if (string.IsNullOrWhiteSpace(observabilityServiceName))
	{
		observabilityServiceName = "music-api";
	}

	builder.Services
		.AddOpenTelemetry()
		.ConfigureResource(resource => resource.AddService(observabilityServiceName))
		.WithMetrics(metrics => metrics
			.AddMeter(OnlineMusicTelemetry.MeterName)
			.AddAspNetCoreInstrumentation()
			.AddOtlpExporter(options => options.Endpoint = otlpEndpoint));
}

builder.Services.AddHttpContextAccessor();
builder.Services.AddSingleton(TimeProvider.System);

builder.Services.AddSingleton<IRefreshTokenStore, SqliteRefreshTokenStore>();
builder.Services.AddSingleton<IAuthService>(sp => new AuthService(
	sp.GetRequiredService<IConfiguration>(),
	sp.GetRequiredService<IHostEnvironment>(),
	sp.GetRequiredService<IRefreshTokenStore>()));
builder.Services.AddSingleton<IAdminCredentialService, AdminCredentialService>();
builder.Services.AddSingleton<IPlaylistStore, SqliteStore>();
builder.Services.AddSingleton<IScanSourceStore, SqliteScanSourceStore>();
builder.Services.AddSingleton<IAuditLogStore, SqliteAuditLogStore>();
builder.Services.AddSingleton<IMusicScanService, MusicScanService>();
builder.Services.AddMemoryCache();
builder.Services.AddSingleton<IOnlineMusicRequestLimiter, OnlineMusicRequestLimiter>();
builder.Services.AddSingleton<IOnlineMusicSearchService, OnlineMusicSearchService>();
builder.Services.AddSingleton<IOnlineMusicPlaybackService, OnlineMusicPlaybackService>();
builder.Services.AddSingleton<IOnlineMusicAssetService, OnlineMusicAssetService>();
builder.Services.AddSingleton<OnlineMusicCircuitBreaker>();
builder.Services.AddTransient<CorrelationIdHandler>();
builder.Services.AddTransient<OnlineMusicResilienceHandler>();
builder.Services
	.AddHttpClient<IOnlineMusicGateway, GoMusicDlGateway>()
	.AddHttpMessageHandler<OnlineMusicResilienceHandler>()
	.AddHttpMessageHandler<CorrelationIdHandler>();
builder.Services
	.AddHttpClient(OnlineMusicSidecarHealthCheck.HttpClientName, client =>
		client.Timeout = Timeout.InfiniteTimeSpan)
	.AddHttpMessageHandler<CorrelationIdHandler>();
builder.Services
	.AddHealthChecks()
	.AddCheck<OnlineMusicSidecarHealthCheck>(
		"online_music_sidecar",
		tags: ["ready"]);
builder.Services.AddHostedService<ScheduledMusicScanWorker>();
builder.Services
	.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
	.AddCookie(options =>
	{
		options.Cookie.Name = "FlutterMusic.Admin";
		options.Cookie.HttpOnly = true;
		options.Cookie.SameSite = SameSiteMode.Strict;
		options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
		options.LoginPath = "/admin/login";
		options.AccessDeniedPath = "/admin/login";
		options.ExpireTimeSpan = TimeSpan.FromHours(4);
		options.SlidingExpiration = true;
	});
builder.Services.AddAuthorization(options =>
	options.AddPolicy(
		AdminAuthorization.PolicyName,
		policy => policy.RequireRole(AdminAuthorization.RoleName)));
builder.Services.AddRazorPages();
var corsAllowedOrigins = CorsOriginPolicy.GetAllowedOrigins(builder.Configuration);
builder.Services.AddCors(options =>
	options.AddDefaultPolicy(policy => CorsOriginPolicy.Configure(policy, corsAllowedOrigins))
);

var app = builder.Build();
_ = app.Services.GetRequiredService<IAuthService>();
_ = app.Services.GetRequiredService<IMusicScanService>();
_ = app.Services.GetRequiredService<IOnlineMusicRequestLimiter>();
_ = app.Services.GetRequiredService<IOnlineMusicGateway>();
_ = app.Services.GetRequiredService<IAdminCredentialService>();
_ = app.Services.GetRequiredService<IPlaylistStore>();
_ = app.Services.GetRequiredService<IScanSourceStore>();
_ = app.Services.GetRequiredService<IAuditLogStore>();
_ = app.Services.GetRequiredService<IOnlineMusicSearchService>();
_ = app.Services.GetRequiredService<IOnlineMusicPlaybackService>();
_ = app.Services.GetRequiredService<IOnlineMusicAssetService>();
// 反向代理（宿主机 Nginx / 容器入口）后面必须显式启用转发头中间件，
// 否则 Connection.RemoteIpAddress 与 Request.Scheme 都是代理的地址和 http：
// 在线搜索限流的按 IP 维度会退化成全站共享一个配额，审计日志也记不到真实客户端。
// KnownProxies/KnownIPNetworks 保持默认值（仅信任回环地址），
// 因此同机代理生效，而直接从公网送来的 X-Forwarded-For 会被忽略。
// 只接受 For/Proto：应用用 AllowedHosts 做主机校验，不能信任客户端可伪造的 X-Forwarded-Host。
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
	ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
});
app.UseMiddleware<CorrelationIdMiddleware>();
app.UseStaticFiles();
app.Use(async (context, next) =>
{
	if (context.Request.Path.StartsWithSegments("/admin"))
	{
		context.Response.Headers.ContentSecurityPolicy = "default-src 'self'; style-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'";
		context.Response.Headers.XContentTypeOptions = "nosniff";
		context.Response.Headers.XFrameOptions = "DENY";
	}

	await next(context);
});
app.UseRouting();
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.UseMiddleware<AuditLogMiddleware>();

app.MapGet("/", () => Results.Ok(new
{
	name = "SimulGroove Music API",
	version = "1.0.0",
	// documentation = "docs/api.md (repository)",
	openapi = "/openapi.json",
	scanningConsole = "/admin/scanning"
}));

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapHealthChecks("/health/ready", new()
{
	Predicate = registration => registration.Tags.Contains("ready")
});
app.MapGet("/openapi.json", () => Results.Json(OpenApiDocument.Create()));
app.MapAuthEndpoints();
app.MapPlaylistEndpoints();
app.MapScanSourceEndpoints();
app.MapAuditLogEndpoints();
app.MapOnlineMusicEndpoints();
app.MapRazorPages();

app.Run();
