using Music.Api.Models;

namespace Music.Api.Data;

public interface IAuditLogStore
{
    void Record(AuditLogEntry entry);

    AuditLogPageResponse Query(
        string username,
        string? level,
        string? eventType,
        string? search,
        DateTimeOffset? from,
        DateTimeOffset? to,
        int page,
        int pageSize);
}
