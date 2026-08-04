using System.Globalization;
using Microsoft.Data.Sqlite;
using Music.Api.Models;

namespace Music.Api.Data;

public sealed class SqliteAuditLogStore : IAuditLogStore
{
    private readonly object _gate = new();
    private readonly string _connectionString;
    private readonly int _retentionDays;

    public SqliteAuditLogStore(IConfiguration configuration, IHostEnvironment environment)
    {
        var configuredPath = configuration["Database:Path"] ?? "storage/music.db";
        var databasePath = Path.IsPathRooted(configuredPath)
            ? configuredPath
            : Path.GetFullPath(Path.Combine(environment.ContentRootPath, configuredPath));
        var directory = Path.GetDirectoryName(databasePath);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        _connectionString = new SqliteConnectionStringBuilder { DataSource = databasePath }.ToString();
        _retentionDays = Math.Clamp(configuration.GetValue("Audit:RetentionDays", 90), 7, 3650);
        Initialize();
    }

    public void Record(AuditLogEntry entry)
    {
        lock (_gate)
        {
            var now = entry.CreatedAt.ToUniversalTime();
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO audit_logs(id, username, level, event_type, message, created_at, method, path, status_code, duration_ms, ip_address, trace_id, details)
                VALUES ($id, $username, $level, $eventType, $message, $createdAt, $method, $path, $statusCode, $durationMs, $ipAddress, $traceId, $details);
                DELETE FROM audit_logs WHERE created_at < $cutoff;
                """;
            command.Parameters.AddWithValue("$id", Guid.NewGuid().ToString("N"));
            command.Parameters.AddWithValue("$username", (object?)entry.Username ?? DBNull.Value);
            command.Parameters.AddWithValue("$level", entry.Level);
            command.Parameters.AddWithValue("$eventType", entry.EventType);
            command.Parameters.AddWithValue("$message", entry.Message.Length > 1000 ? entry.Message[..1000] : entry.Message);
            command.Parameters.AddWithValue("$createdAt", Format(now));
            command.Parameters.AddWithValue("$method", (object?)entry.Method ?? DBNull.Value);
            command.Parameters.AddWithValue("$path", (object?)entry.Path ?? DBNull.Value);
            command.Parameters.AddWithValue("$statusCode", (object?)entry.StatusCode ?? DBNull.Value);
            command.Parameters.AddWithValue("$durationMs", (object?)entry.DurationMs ?? DBNull.Value);
            command.Parameters.AddWithValue("$ipAddress", (object?)entry.IpAddress ?? DBNull.Value);
            command.Parameters.AddWithValue("$traceId", (object?)entry.TraceId ?? DBNull.Value);
            command.Parameters.AddWithValue("$details", (object?)entry.Details ?? DBNull.Value);
            command.Parameters.AddWithValue("$cutoff", Format(now.AddDays(-_retentionDays)));
            command.ExecuteNonQuery();
        }
    }

    public AuditLogPageResponse Query(
        string username,
        string? level,
        string? eventType,
        string? search,
        DateTimeOffset? from,
        DateTimeOffset? to,
        int page,
        int pageSize)
    {
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 100);
        lock (_gate)
        {
            using var connection = OpenConnection();
            var where = new List<string> { "username = $username" };
            using var count = connection.CreateCommand();
            count.Parameters.AddWithValue("$username", username);
            AddFilters(count, where, level, eventType, search, from, to);
            count.CommandText = $"SELECT COUNT(*) FROM audit_logs WHERE {string.Join(" AND ", where)}";
            var total = Convert.ToInt32(count.ExecuteScalar(), CultureInfo.InvariantCulture);

            using var command = connection.CreateCommand();
            command.Parameters.AddWithValue("$username", username);
            AddFilters(command, where = new List<string> { "username = $username" }, level, eventType, search, from, to);
            command.CommandText = $"SELECT id, username, level, event_type, message, created_at, method, path, status_code, duration_ms, ip_address, trace_id, details FROM audit_logs WHERE {string.Join(" AND ", where)} ORDER BY created_at DESC LIMIT $limit OFFSET $offset";
            command.Parameters.AddWithValue("$limit", pageSize);
            command.Parameters.AddWithValue("$offset", (page - 1) * pageSize);
            using var reader = command.ExecuteReader();
            var items = new List<AuditLogResponse>();
            while (reader.Read())
            {
                items.Add(new AuditLogResponse(
                    reader.GetString(0),
                    reader.IsDBNull(1) ? null : reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    Parse(reader.GetString(5)),
                    reader.IsDBNull(6) ? null : reader.GetString(6),
                    reader.IsDBNull(7) ? null : reader.GetString(7),
                    reader.IsDBNull(8) ? null : reader.GetInt32(8),
                    reader.IsDBNull(9) ? null : reader.GetInt32(9),
                    reader.IsDBNull(10) ? null : reader.GetString(10),
                    reader.IsDBNull(11) ? null : reader.GetString(11),
                    reader.IsDBNull(12) ? null : reader.GetString(12)));
            }
            return new AuditLogPageResponse(items, total, page, pageSize);
        }
    }

    private static void AddFilters(
        SqliteCommand command,
        List<string> where,
        string? level,
        string? eventType,
        string? search,
        DateTimeOffset? from,
        DateTimeOffset? to)
    {
        if (!string.IsNullOrWhiteSpace(level))
        {
            where.Add("level = $level");
            command.Parameters.AddWithValue("$level", level.Trim().ToLowerInvariant());
        }
        if (!string.IsNullOrWhiteSpace(eventType))
        {
            where.Add("event_type = $eventType");
            command.Parameters.AddWithValue("$eventType", eventType.Trim());
        }
        if (!string.IsNullOrWhiteSpace(search))
        {
            where.Add("(message LIKE $search OR event_type LIKE $search OR path LIKE $search OR details LIKE $search)");
            command.Parameters.AddWithValue("$search", $"%{search.Trim()}%");
        }
        if (from is not null)
        {
            where.Add("created_at >= $from");
            command.Parameters.AddWithValue("$from", Format(from.Value));
        }
        if (to is not null)
        {
            where.Add("created_at <= $to");
            command.Parameters.AddWithValue("$to", Format(to.Value));
        }
    }

    private void Initialize()
    {
        using var connection = OpenConnection();
        using var command = connection.CreateCommand();
        command.CommandText = """
            CREATE TABLE IF NOT EXISTS audit_logs (
                id TEXT PRIMARY KEY,
                username TEXT NULL,
                level TEXT NOT NULL,
                event_type TEXT NOT NULL,
                message TEXT NOT NULL,
                created_at TEXT NOT NULL,
                method TEXT NULL,
                path TEXT NULL,
                status_code INTEGER NULL,
                duration_ms INTEGER NULL,
                ip_address TEXT NULL,
                trace_id TEXT NULL,
                details TEXT NULL
            );
            CREATE INDEX IF NOT EXISTS ix_audit_logs_user_time ON audit_logs(username, created_at DESC);
            CREATE INDEX IF NOT EXISTS ix_audit_logs_event ON audit_logs(event_type, created_at DESC);
            """;
        command.ExecuteNonQuery();
    }

    private SqliteConnection OpenConnection()
    {
        var connection = new SqliteConnection(_connectionString);
        connection.Open();
        using var pragma = connection.CreateCommand();
        pragma.CommandText = "PRAGMA foreign_keys = ON";
        pragma.ExecuteNonQuery();
        return connection;
    }

    private static DateTimeOffset Parse(string value) => DateTimeOffset.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
    private static string Format(DateTimeOffset value) => value.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);
}
