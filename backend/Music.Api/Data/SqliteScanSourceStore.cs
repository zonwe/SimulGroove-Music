using System.Globalization;
using Microsoft.Data.Sqlite;
using Music.Api.Models;

namespace Music.Api.Data;

public sealed class SqliteScanSourceStore : IScanSourceStore
{
    private readonly object _gate = new();
    private readonly string _connectionString;

    public SqliteScanSourceStore(IConfiguration configuration, IHostEnvironment environment)
    {
        var configuredPath = configuration["Database:Path"] ?? "storage/music.db";
        var databasePath = Path.IsPathRooted(configuredPath)
            ? configuredPath
            : Path.GetFullPath(Path.Combine(environment.ContentRootPath, configuredPath));
        var directory = Path.GetDirectoryName(databasePath);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        _connectionString = new SqliteConnectionStringBuilder { DataSource = databasePath }.ToString();
        Initialize();
    }

    public IReadOnlyList<ScanSourceResponse> GetForUser(string username)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT id, path, interval_minutes, enabled, status, track_count, last_scan_at, next_scan_at, last_error FROM scan_sources WHERE username = $username ORDER BY created_at";
            command.Parameters.AddWithValue("$username", username);
            return ReadSources(command);
        }
    }

    public IReadOnlyList<ScheduledScanSource> GetDue(DateTimeOffset now)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT id, username FROM scan_sources WHERE enabled = 1 AND status <> 'scanning' AND next_scan_at <= $now ORDER BY next_scan_at LIMIT 20";
            command.Parameters.AddWithValue("$now", Format(now));
            using var reader = command.ExecuteReader();
            var result = new List<ScheduledScanSource>();
            while (reader.Read()) result.Add(new ScheduledScanSource(reader.GetString(0), reader.GetString(1)));
            return result;
        }
    }

    public ScanSourceResponse? Get(string username, string id)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT id, path, interval_minutes, enabled, status, track_count, last_scan_at, next_scan_at, last_error FROM scan_sources WHERE username = $username AND id = $id";
            command.Parameters.AddWithValue("$username", username);
            command.Parameters.AddWithValue("$id", id);
            return ReadSources(command).SingleOrDefault();
        }
    }

    public ScanSourceResponse Create(string username, string path, int intervalMinutes, bool enabled)
    {
        lock (_gate)
        {
            var now = DateTimeOffset.UtcNow;
            var id = Guid.NewGuid().ToString("N");
            using var connection = OpenConnection();
            using var transaction = connection.BeginTransaction();
            EnsureAccount(connection, transaction, username);
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = "INSERT INTO scan_sources(id, username, path, interval_minutes, enabled, status, track_count, last_scan_at, next_scan_at, last_error, created_at, updated_at) VALUES ($id, $username, $path, $interval, $enabled, 'idle', 0, NULL, $nextScanAt, NULL, $now, $now)";
            command.Parameters.AddWithValue("$id", id);
            command.Parameters.AddWithValue("$username", username);
            command.Parameters.AddWithValue("$path", path);
            command.Parameters.AddWithValue("$interval", intervalMinutes);
            command.Parameters.AddWithValue("$enabled", enabled ? 1 : 0);
            command.Parameters.AddWithValue("$nextScanAt", Format(enabled ? now : now.AddMinutes(intervalMinutes)));
            command.Parameters.AddWithValue("$now", Format(now));
            try
            {
                command.ExecuteNonQuery();
            }
            catch (SqliteException exception) when (IsUniqueConstraint(exception))
            {
                throw new DuplicateScanSourceException(path, exception);
            }

            transaction.Commit();
            return Get(username, id)!;
        }
    }

    public ScanSourceResponse? Update(string username, string id, string path, int intervalMinutes, bool enabled)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = "UPDATE scan_sources SET path = $path, interval_minutes = $interval, enabled = $enabled, next_scan_at = CASE WHEN $enabled = 1 THEN $nextScanAt ELSE next_scan_at END, updated_at = $now WHERE username = $username AND id = $id";
            command.Parameters.AddWithValue("$path", path);
            command.Parameters.AddWithValue("$interval", intervalMinutes);
            command.Parameters.AddWithValue("$enabled", enabled ? 1 : 0);
            command.Parameters.AddWithValue("$nextScanAt", Format(DateTimeOffset.UtcNow));
            command.Parameters.AddWithValue("$now", Format(DateTimeOffset.UtcNow));
            command.Parameters.AddWithValue("$username", username);
            command.Parameters.AddWithValue("$id", id);
            try
            {
                if (command.ExecuteNonQuery() == 0) return null;
            }
            catch (SqliteException exception) when (IsUniqueConstraint(exception))
            {
                throw new DuplicateScanSourceException(path, exception);
            }

            return Get(username, id);
        }
    }

    public bool Delete(string username, string id)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = "DELETE FROM scan_sources WHERE username = $username AND id = $id";
            command.Parameters.AddWithValue("$username", username);
            command.Parameters.AddWithValue("$id", id);
            return command.ExecuteNonQuery() > 0;
        }
    }

    public bool TryStartScan(string id)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = "UPDATE scan_sources SET status = 'scanning', last_error = NULL, updated_at = $now WHERE id = $id AND status <> 'scanning'";
            command.Parameters.AddWithValue("$id", id);
            command.Parameters.AddWithValue("$now", Format(DateTimeOffset.UtcNow));
            return command.ExecuteNonQuery() > 0;
        }
    }

    public void CompleteScan(string id, string runId, IReadOnlyList<DiscoveredTrack> tracks, DateTimeOffset completedAt)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var transaction = connection.BeginTransaction();
            var source = GetById(connection, transaction, id) ?? throw new InvalidOperationException("Scan source no longer exists.");
            foreach (var track in tracks)
            {
                using var command = connection.CreateCommand();
                command.Transaction = transaction;
                command.CommandText = "INSERT INTO library_tracks(id, username, scan_source_id, file_path, title, artist, album, extension, file_size, modified_at, last_seen_scan_id, created_at, updated_at) VALUES ($id, $username, $sourceId, $filePath, $title, $artist, $album, $extension, $fileSize, $modifiedAt, $runId, $now, $now) ON CONFLICT(username, file_path) DO UPDATE SET scan_source_id = excluded.scan_source_id, title = excluded.title, artist = excluded.artist, album = excluded.album, extension = excluded.extension, file_size = excluded.file_size, modified_at = excluded.modified_at, last_seen_scan_id = excluded.last_seen_scan_id, updated_at = excluded.updated_at";
                command.Parameters.AddWithValue("$id", Guid.NewGuid().ToString("N"));
                command.Parameters.AddWithValue("$username", source.Username);
                command.Parameters.AddWithValue("$sourceId", id);
                command.Parameters.AddWithValue("$filePath", track.FilePath);
                command.Parameters.AddWithValue("$title", track.Title);
                command.Parameters.AddWithValue("$artist", track.Artist);
                command.Parameters.AddWithValue("$album", track.Album);
                command.Parameters.AddWithValue("$extension", track.Extension);
                command.Parameters.AddWithValue("$fileSize", track.FileSize);
                command.Parameters.AddWithValue("$modifiedAt", Format(track.ModifiedAt));
                command.Parameters.AddWithValue("$runId", runId);
                command.Parameters.AddWithValue("$now", Format(completedAt));
                command.ExecuteNonQuery();
            }

            using (var deleteMissing = connection.CreateCommand())
            {
                deleteMissing.Transaction = transaction;
                deleteMissing.CommandText = "DELETE FROM library_tracks WHERE scan_source_id = $sourceId AND last_seen_scan_id <> $runId";
                deleteMissing.Parameters.AddWithValue("$sourceId", id);
                deleteMissing.Parameters.AddWithValue("$runId", runId);
                deleteMissing.ExecuteNonQuery();
            }

            using var complete = connection.CreateCommand();
            complete.Transaction = transaction;
            complete.CommandText = "UPDATE scan_sources SET status = 'idle', track_count = $count, last_scan_at = $completedAt, next_scan_at = $nextScanAt, last_error = NULL, updated_at = $completedAt WHERE id = $id";
            complete.Parameters.AddWithValue("$count", tracks.Count);
            complete.Parameters.AddWithValue("$completedAt", Format(completedAt));
            complete.Parameters.AddWithValue("$nextScanAt", Format(completedAt.AddMinutes(source.IntervalMinutes)));
            complete.Parameters.AddWithValue("$id", id);
            complete.ExecuteNonQuery();
            transaction.Commit();
        }
    }

    public void FailScan(string id, string error, DateTimeOffset failedAt)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            var source = GetById(connection, null, id);
            if (source is null) return;
            using var command = connection.CreateCommand();
            command.CommandText = "UPDATE scan_sources SET status = 'failed', last_error = $error, last_scan_at = $failedAt, next_scan_at = $nextScanAt, updated_at = $failedAt WHERE id = $id";
            command.Parameters.AddWithValue("$error", error.Length > 1000 ? error[..1000] : error);
            command.Parameters.AddWithValue("$failedAt", Format(failedAt));
            command.Parameters.AddWithValue("$nextScanAt", Format(failedAt.AddMinutes(source.IntervalMinutes)));
            command.Parameters.AddWithValue("$id", id);
            command.ExecuteNonQuery();
        }
    }

    public IReadOnlyList<ScannedTrackResponse> GetTracks(string username, string sourceId, int limit)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT t.id, t.scan_source_id, t.file_path, t.title, t.artist, t.album, t.extension, t.file_size, t.modified_at FROM library_tracks t JOIN scan_sources s ON s.id = t.scan_source_id WHERE t.username = $username AND t.scan_source_id = $sourceId AND s.username = $username ORDER BY t.title LIMIT $limit";
            command.Parameters.AddWithValue("$username", username);
            command.Parameters.AddWithValue("$sourceId", sourceId);
            command.Parameters.AddWithValue("$limit", Math.Clamp(limit, 1, 1000));
            using var reader = command.ExecuteReader();
            var result = new List<ScannedTrackResponse>();
            while (reader.Read())
            {
                result.Add(ReadTrack(reader));
            }
            return result;
        }
    }

    public ScannedTrackResponse? GetTrack(string username, string sourceId, string trackId)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT t.id, t.scan_source_id, t.file_path, t.title, t.artist, t.album, t.extension, t.file_size, t.modified_at FROM library_tracks t JOIN scan_sources s ON s.id = t.scan_source_id WHERE t.username = $username AND t.scan_source_id = $sourceId AND t.id = $trackId AND s.username = $username";
            command.Parameters.AddWithValue("$username", username);
            command.Parameters.AddWithValue("$sourceId", sourceId);
            command.Parameters.AddWithValue("$trackId", trackId);
            using var reader = command.ExecuteReader();
            return reader.Read() ? ReadTrack(reader) : null;
        }
    }

    private void Initialize()
    {
        using var connection = OpenConnection();
        using var command = connection.CreateCommand();
        command.CommandText = """
            CREATE TABLE IF NOT EXISTS accounts (
                username TEXT PRIMARY KEY,
                remote_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                avatar_uri TEXT NULL
            );
            CREATE TABLE IF NOT EXISTS scan_sources (
                id TEXT PRIMARY KEY,
                username TEXT NOT NULL REFERENCES accounts(username) ON DELETE CASCADE,
                path TEXT NOT NULL COLLATE NOCASE,
                interval_minutes INTEGER NOT NULL,
                enabled INTEGER NOT NULL,
                status TEXT NOT NULL,
                track_count INTEGER NOT NULL,
                last_scan_at TEXT NULL,
                next_scan_at TEXT NOT NULL,
                last_error TEXT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(username, path)
            );
            CREATE TABLE IF NOT EXISTS library_tracks (
                id TEXT PRIMARY KEY,
                username TEXT NOT NULL REFERENCES accounts(username) ON DELETE CASCADE,
                scan_source_id TEXT NOT NULL REFERENCES scan_sources(id) ON DELETE CASCADE,
                file_path TEXT NOT NULL COLLATE NOCASE,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT NOT NULL,
                extension TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                modified_at TEXT NOT NULL,
                last_seen_scan_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(username, file_path)
            );
            CREATE INDEX IF NOT EXISTS ix_scan_sources_due ON scan_sources(enabled, next_scan_at);
            CREATE INDEX IF NOT EXISTS ix_library_tracks_source ON library_tracks(scan_source_id);
            UPDATE scan_sources SET status = 'idle', next_scan_at = CURRENT_TIMESTAMP WHERE status = 'scanning';
            """;
        command.ExecuteNonQuery();
    }

    private static void EnsureAccount(SqliteConnection connection, SqliteTransaction transaction, string username)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO accounts(username, remote_id, display_name, avatar_uri)
            VALUES ($username, $remoteId, $displayName, NULL)
            ON CONFLICT(username) DO NOTHING
            """;
        command.Parameters.AddWithValue("$username", username);
        command.Parameters.AddWithValue("$remoteId", $"account-{username}");
        command.Parameters.AddWithValue("$displayName", username.Split('@')[0]);
        command.ExecuteNonQuery();
    }

    private static bool IsUniqueConstraint(SqliteException exception) =>
        exception.SqliteExtendedErrorCode == 2067;

    private SqliteConnection OpenConnection()
    {
        var connection = new SqliteConnection(_connectionString);
        connection.Open();
        using var pragma = connection.CreateCommand();
        pragma.CommandText = "PRAGMA foreign_keys = ON";
        pragma.ExecuteNonQuery();
        return connection;
    }

    private static IReadOnlyList<ScanSourceResponse> ReadSources(SqliteCommand command)
    {
        using var reader = command.ExecuteReader();
        var result = new List<ScanSourceResponse>();
        while (reader.Read())
        {
            result.Add(new ScanSourceResponse(reader.GetString(0), reader.GetString(1), reader.GetInt32(2), reader.GetInt32(3) == 1, reader.GetString(4), reader.GetInt32(5), NullableDate(reader, 6), NullableDate(reader, 7), reader.IsDBNull(8) ? null : reader.GetString(8)));
        }
        return result;
    }

    private static ScannedTrackResponse ReadTrack(SqliteDataReader reader) => new(
        reader.GetString(0),
        reader.GetString(1),
        reader.GetString(2),
        reader.GetString(3),
        reader.GetString(4),
        reader.GetString(5),
        reader.GetString(6),
        reader.GetInt64(7),
        Parse(reader.GetString(8)));

    private static StoredSource? GetById(SqliteConnection connection, SqliteTransaction? transaction, string id)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT username, interval_minutes FROM scan_sources WHERE id = $id";
        command.Parameters.AddWithValue("$id", id);
        using var reader = command.ExecuteReader();
        return reader.Read() ? new StoredSource(reader.GetString(0), reader.GetInt32(1)) : null;
    }

    private static DateTimeOffset? NullableDate(SqliteDataReader reader, int ordinal) => reader.IsDBNull(ordinal) ? null : Parse(reader.GetString(ordinal));
    private static DateTimeOffset Parse(string value) => DateTimeOffset.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
    private static string Format(DateTimeOffset value) => value.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);
    private sealed record StoredSource(string Username, int IntervalMinutes);
}
