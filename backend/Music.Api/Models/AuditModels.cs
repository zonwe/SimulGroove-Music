namespace Music.Api.Models;

public sealed record AuditLogEntry(
    string? Username,
    string Level,
    string EventType,
    string Message,
    DateTimeOffset CreatedAt,
    string? Method = null,
    string? Path = null,
    int? StatusCode = null,
    int? DurationMs = null,
    string? IpAddress = null,
    string? TraceId = null,
    string? Details = null);

public sealed record AuditLogResponse(
    string Id,
    string? Username,
    string Level,
    string EventType,
    string Message,
    DateTimeOffset CreatedAt,
    string? Method,
    string? Path,
    int? StatusCode,
    int? DurationMs,
    string? IpAddress,
    string? TraceId,
    string? Details);

public sealed record AuditLogPageResponse(
    IReadOnlyList<AuditLogResponse> Items,
    int Total,
    int Page,
    int PageSize);
