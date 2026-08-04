using System.Text.Json.Serialization;
using Music.Api.Data;
using Music.Api.Endpoints;
using Music.Api.OpenApi;
using Music.Api.Services;
using Music.Api.Services.Scanning;
using Music.Api.Middleware;

var builder = WebApplication.CreateBuilder(args);

builder.Services.ConfigureHttpJsonOptions(options =>
{
	options.SerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
	options.SerializerOptions.PropertyNameCaseInsensitive = true;
	options.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.Never;
});

builder.Services.AddSingleton<IAuthService, AuthService>();
builder.Services.AddSingleton<IPlaylistStore, SqliteStore>();
builder.Services.AddSingleton<IScanSourceStore, SqliteScanSourceStore>();
builder.Services.AddSingleton<IAuditLogStore, SqliteAuditLogStore>();
builder.Services.AddSingleton<IMusicScanService, MusicScanService>();
builder.Services.AddHostedService<ScheduledMusicScanWorker>();
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
_ = app.Services.GetRequiredService<IPlaylistStore>();
_ = app.Services.GetRequiredService<IScanSourceStore>();
_ = app.Services.GetRequiredService<IAuditLogStore>();
app.UseCors();
app.UseMiddleware<AuditLogMiddleware>();

app.MapGet("/", () => Results.Ok(new
{
	name = "Flutter Music API",
	version = "1.0.0",
	documentation = "docs/api.md (repository)",
	openapi = "/openapi.json"
}));

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapGet("/openapi.json", () => Results.Json(OpenApiDocument.Create()));
app.MapAuthEndpoints();
app.MapPlaylistEndpoints();
app.MapScanSourceEndpoints();
app.MapAuditLogEndpoints();

app.Run();
