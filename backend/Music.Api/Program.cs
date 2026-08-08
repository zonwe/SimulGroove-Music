using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.Cookies;
using Music.Api.Data;
using Music.Api.Endpoints;
using Music.Api.Middleware;
using Music.Api.OpenApi;
using Music.Api.Services;
using Music.Api.Services.Administration;
using Music.Api.Services.OnlineMusic;
using Music.Api.Services.Scanning;

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

builder.Services.AddSingleton<IAuthService, AuthService>();
builder.Services.AddSingleton<IAdminCredentialService, AdminCredentialService>();
builder.Services.AddSingleton<IPlaylistStore, SqliteStore>();
builder.Services.AddSingleton<IScanSourceStore, SqliteScanSourceStore>();
builder.Services.AddSingleton<IAuditLogStore, SqliteAuditLogStore>();
builder.Services.AddSingleton<IMusicScanService, MusicScanService>();
builder.Services.AddMemoryCache();
builder.Services.AddSingleton<IOnlineMusicRequestLimiter, OnlineMusicRequestLimiter>();
builder.Services.AddSingleton<IOnlineMusicSearchService, OnlineMusicSearchService>();
builder.Services.AddSingleton<IOnlineMusicPlaybackService, OnlineMusicPlaybackService>();
builder.Services.AddHttpClient<IOnlineMusicGateway, GoMusicDlGateway>();
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
builder.Services.AddCors(options =>
	options.AddDefaultPolicy(policy =>
		policy
			.AllowAnyOrigin()
			.AllowAnyHeader()
			.AllowAnyMethod()
	)
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
app.UseCors();
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
app.UseAuthentication();
app.UseAuthorization();
app.UseMiddleware<AuditLogMiddleware>();

app.MapGet("/", () => Results.Ok(new
{
	name = "Flutter Music API",
	version = "1.0.0",
	// documentation = "docs/api.md (repository)",
	openapi = "/openapi.json",
	scanningConsole = "/admin/scanning"
}));

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapGet("/openapi.json", () => Results.Json(OpenApiDocument.Create()));
app.MapAuthEndpoints();
app.MapPlaylistEndpoints();
app.MapScanSourceEndpoints();
app.MapAuditLogEndpoints();
app.MapOnlineMusicEndpoints();
app.MapRazorPages();

app.Run();
