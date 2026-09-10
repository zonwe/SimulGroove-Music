using System.Globalization;
using Microsoft.Data.Sqlite;
using Music.Api.Models;

namespace Music.Api.Data;

public sealed class SqliteStore : IPlaylistStore
{
    private readonly object _gate = new();
    private readonly string _connectionString;

    public SqliteStore(IConfiguration configuration, IHostEnvironment environment)
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

    private SqliteConnection OpenConnection()
    {
        var connection = new SqliteConnection(_connectionString);
        connection.Open();
        using var pragma = connection.CreateCommand();
        pragma.CommandText = "PRAGMA foreign_keys = ON";
        pragma.ExecuteNonQuery();
        return connection;
    }

    private void Initialize()
    {
        using var connection = OpenConnection();
        using var command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS accounts (
                username TEXT PRIMARY KEY,
                remote_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                avatar_uri TEXT NULL
            );
            CREATE TABLE IF NOT EXISTS playlists (
                username TEXT NOT NULL REFERENCES accounts(username) ON DELETE CASCADE,
                remote_id TEXT NOT NULL,
                name TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (username, remote_id)
            );
            CREATE TABLE IF NOT EXISTS playlist_tracks (
                username TEXT NOT NULL,
                remote_id TEXT NOT NULL,
                uri TEXT NOT NULL,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT NOT NULL,
                duration_ms INTEGER NULL,
                match_token TEXT NULL,
                PRIMARY KEY (username, remote_id, uri),
                FOREIGN KEY (username, remote_id) REFERENCES playlists(username, remote_id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS liked_tracks (
                username TEXT NOT NULL REFERENCES accounts(username) ON DELETE CASCADE,
                uri TEXT NOT NULL,
                title TEXT NOT NULL,
                artist TEXT NOT NULL,
                album TEXT NOT NULL,
                duration_ms INTEGER NULL,
                added_at TEXT NOT NULL,
                match_token TEXT NULL,
                PRIMARY KEY (username, uri)
            );
            CREATE TABLE IF NOT EXISTS equalizer_presets (
                username TEXT NOT NULL REFERENCES accounts(username) ON DELETE CASCADE,
                remote_id TEXT NOT NULL,
                name TEXT NOT NULL,
                gains_json TEXT NOT NULL,
                preamp_db REAL NOT NULL DEFAULT 0.0,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (username, remote_id)
            );
            CREATE TABLE IF NOT EXISTS sync_tombstones (
                username TEXT NOT NULL REFERENCES accounts(username) ON DELETE CASCADE,
                entity_type TEXT NOT NULL,
                remote_key TEXT NOT NULL,
                deleted_at TEXT NOT NULL,
                PRIMARY KEY (username, entity_type, remote_key)
            );
            """;
        command.ExecuteNonQuery();
        EnsureColumn(connection, "playlist_tracks", "match_token", "TEXT NULL");
        EnsureColumn(connection, "liked_tracks", "match_token", "TEXT NULL");
        using var index = connection.CreateCommand();
        index.CommandText = """
            CREATE INDEX IF NOT EXISTS ix_playlist_tracks_match_token
                ON playlist_tracks(username, match_token);
            CREATE UNIQUE INDEX IF NOT EXISTS ux_liked_tracks_match_token
                ON liked_tracks(username, match_token)
                WHERE match_token IS NOT NULL;
            """;
        index.ExecuteNonQuery();
    }

    private static void EnsureColumn(
        SqliteConnection connection,
        string table,
        string column,
        string definition)
    {
        using var check = connection.CreateCommand();
        check.CommandText = $"PRAGMA table_info({table})";
        using var reader = check.ExecuteReader();
        while (reader.Read())
        {
            if (string.Equals(
                    reader.GetString(1),
                    column,
                    StringComparison.OrdinalIgnoreCase)) return;
        }
        reader.Close();
        using var alter = connection.CreateCommand();
        alter.CommandText = $"ALTER TABLE {table} ADD COLUMN {column} {definition}";
        alter.ExecuteNonQuery();
    }

    private void EnsureAccount(SqliteConnection connection, SqliteTransaction? transaction, string username)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO accounts(username, remote_id, display_name, avatar_uri)
            VALUES ($username, $remoteId, $displayName, NULL)
            ON CONFLICT(username) DO NOTHING;
            """;
        command.Parameters.AddWithValue("$username", username);
        command.Parameters.AddWithValue("$remoteId", $"account-{username}");
        command.Parameters.AddWithValue("$displayName", username.Split('@')[0]);
        command.ExecuteNonQuery();
    }

    public LibrarySyncResponse SyncLibrary(
        string username,
        IReadOnlyList<PlaylistRequest> incomingPlaylists,
        IReadOnlyList<TrackRequest> incomingLikedTracks,
        IReadOnlyList<EqualizerPresetRequest> incomingEqualizerPresets,
        IReadOnlyList<SyncDeletionRequest>? incomingDeletions = null)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var transaction = connection.BeginTransaction();
            EnsureAccount(connection, transaction, username);
            foreach (var deletion in incomingDeletions ?? [])
            {
                if (!SyncEntityTypes.IsSupported(deletion.EntityType) ||
                    string.IsNullOrWhiteSpace(deletion.RemoteKey) || deletion.DeletedAt is null) continue;
                UpsertTombstone(connection, transaction, username, deletion.EntityType!,
                    deletion.RemoteKey, deletion.DeletedAt.Value);
            }

            foreach (var playlist in incomingPlaylists)
            {
                using var playlistCommand = connection.CreateCommand();
                var remoteId = playlist.RemoteId!;
                var updatedAt = playlist.UpdatedAt ?? DateTimeOffset.UtcNow;
                if (!ShouldAcceptChange(connection, transaction, username,
                        SyncEntityTypes.Playlist, remoteId, updatedAt,
                        "playlists", "remote_id", "updated_at",
                        acceptEqual: () => (playlist.Tracks?.Count ?? 0) >
                            CountPlaylistTracks(connection, transaction, username, remoteId))) continue;

                playlistCommand.Transaction = transaction;
                playlistCommand.CommandText = "INSERT INTO playlists(username, remote_id, name, updated_at) VALUES ($username, $remoteId, $name, $updatedAt) ON CONFLICT(username, remote_id) DO UPDATE SET name = excluded.name, updated_at = excluded.updated_at";
                playlistCommand.Parameters.AddWithValue("$username", username);
                playlistCommand.Parameters.AddWithValue("$remoteId", playlist.RemoteId!);
                playlistCommand.Parameters.AddWithValue("$name", playlist.Name!);
                playlistCommand.Parameters.AddWithValue("$updatedAt", FormatTimestamp(updatedAt));
                playlistCommand.ExecuteNonQuery();

                using var deleteTracks = connection.CreateCommand();
                deleteTracks.Transaction = transaction;
                deleteTracks.CommandText = "DELETE FROM playlist_tracks WHERE username = $username AND remote_id = $remoteId";
                deleteTracks.Parameters.AddWithValue("$username", username);
                deleteTracks.Parameters.AddWithValue("$remoteId", playlist.RemoteId!);
                deleteTracks.ExecuteNonQuery();

                foreach (var track in playlist.Tracks ?? [])
                {
                    using var trackCommand = connection.CreateCommand();
                    trackCommand.Transaction = transaction;
                    trackCommand.CommandText = "INSERT INTO playlist_tracks(username, remote_id, uri, title, artist, album, duration_ms, match_token) VALUES ($username, $remoteId, $uri, $title, $artist, $album, $durationMs, $matchToken)";
                    trackCommand.Parameters.AddWithValue("$username", username);
                    trackCommand.Parameters.AddWithValue("$remoteId", playlist.RemoteId!);
                    trackCommand.Parameters.AddWithValue("$uri", track.Uri ?? string.Empty);
                    trackCommand.Parameters.AddWithValue("$title", track.Title ?? string.Empty);
                    trackCommand.Parameters.AddWithValue("$artist", track.Artist ?? string.Empty);
                    trackCommand.Parameters.AddWithValue("$album", track.Album ?? string.Empty);
                    trackCommand.Parameters.AddWithValue("$durationMs", (object?)track.DurationMs ?? DBNull.Value);
                    trackCommand.Parameters.AddWithValue("$matchToken", (object?)track.MatchToken ?? DBNull.Value);
                    trackCommand.ExecuteNonQuery();
                }
            }
            foreach (var track in incomingLikedTracks)
            {
                if (string.IsNullOrWhiteSpace(track.Uri)) continue;
                using var likedCommand = connection.CreateCommand();
                likedCommand.Transaction = transaction;
                var updatedAt = track.UpdatedAt ?? DateTimeOffset.UtcNow;
                var matchToken = string.IsNullOrEmpty(track.MatchToken)
                    ? null
                    : track.MatchToken;
                var remoteKey = matchToken ?? track.Uri;
                if (!ShouldAcceptChange(connection, transaction, username,
                        SyncEntityTypes.LikedTrack, remoteKey, updatedAt,
                        "liked_tracks",
                        matchToken is null ? "uri" : "match_token",
                        "added_at")) continue;

                if (matchToken is not null)
                {
                    using var removeDuplicate = connection.CreateCommand();
                    removeDuplicate.Transaction = transaction;
                    removeDuplicate.CommandText = """
                        DELETE FROM liked_tracks
                        WHERE username = $username
                          AND match_token = $matchToken
                          AND uri <> $uri;
                        """;
                    removeDuplicate.Parameters.AddWithValue("$username", username);
                    removeDuplicate.Parameters.AddWithValue("$matchToken", matchToken);
                    removeDuplicate.Parameters.AddWithValue("$uri", track.Uri);
                    removeDuplicate.ExecuteNonQuery();
                }

                likedCommand.CommandText = """
                    INSERT INTO liked_tracks(
                        username, uri, title, artist, album, duration_ms,
                        added_at, match_token)
                    VALUES (
                        $username, $uri, $title, $artist, $album, $durationMs,
                        $addedAt, $matchToken)
                    ON CONFLICT(username, uri) DO UPDATE SET
                        title = excluded.title,
                        artist = excluded.artist,
                        album = excluded.album,
                        duration_ms = excluded.duration_ms,
                        added_at = excluded.added_at,
                        match_token = COALESCE(
                            excluded.match_token,
                            liked_tracks.match_token);
                    """;
                likedCommand.Parameters.AddWithValue("$username", username);
                likedCommand.Parameters.AddWithValue("$uri", track.Uri);
                likedCommand.Parameters.AddWithValue("$title", track.Title ?? string.Empty);
                likedCommand.Parameters.AddWithValue("$artist", track.Artist ?? string.Empty);
                likedCommand.Parameters.AddWithValue("$album", track.Album ?? string.Empty);
                likedCommand.Parameters.AddWithValue("$durationMs", (object?)track.DurationMs ?? DBNull.Value);
                likedCommand.Parameters.AddWithValue("$addedAt", FormatTimestamp(updatedAt));
                likedCommand.Parameters.AddWithValue("$matchToken", (object?)matchToken ?? DBNull.Value);
                likedCommand.ExecuteNonQuery();
            }
            foreach (var preset in incomingEqualizerPresets)
            {
                if (string.IsNullOrWhiteSpace(preset.RemoteId) || string.IsNullOrWhiteSpace(preset.Name)) continue;
                using var presetCommand = connection.CreateCommand();
                presetCommand.Transaction = transaction;
                var updatedAt = preset.UpdatedAt ?? DateTimeOffset.UtcNow;
                if (!ShouldAcceptChange(connection, transaction, username,
                        SyncEntityTypes.EqualizerPreset, preset.RemoteId!, updatedAt,
                        "equalizer_presets", "remote_id", "updated_at")) continue;

                presetCommand.CommandText = """
                    INSERT INTO equalizer_presets(username, remote_id, name, gains_json, preamp_db, updated_at)
                    VALUES ($username, $remoteId, $name, $gainsJson, $preampDb, $updatedAt)
                    ON CONFLICT(username, remote_id) DO UPDATE SET
                        name = excluded.name,
                        gains_json = excluded.gains_json,
                        preamp_db = excluded.preamp_db,
                        updated_at = excluded.updated_at;
                    """;
                presetCommand.Parameters.AddWithValue("$username", username);
                presetCommand.Parameters.AddWithValue("$remoteId", preset.RemoteId);
                presetCommand.Parameters.AddWithValue("$name", preset.Name);
                presetCommand.Parameters.AddWithValue("$gainsJson", preset.GainsJson ?? "[]");
                presetCommand.Parameters.AddWithValue("$preampDb", preset.PreampDb ?? 0.0);
                presetCommand.Parameters.AddWithValue("$updatedAt", FormatTimestamp(updatedAt));
                presetCommand.ExecuteNonQuery();
            }
            ApplyTombstones(connection, transaction, username);
            transaction.Commit();

            using var query = connection.CreateCommand();
            query.CommandText = "SELECT remote_id, name, updated_at FROM playlists WHERE username = $username ORDER BY remote_id";
            query.Parameters.AddWithValue("$username", username);
            using var reader = query.ExecuteReader();
            var playlists = new List<PlaylistResponse>();
            while (reader.Read())
            {
                var remoteId = reader.GetString(0);
                playlists.Add(new PlaylistResponse(remoteId, reader.GetString(1), DateTimeOffset.Parse(reader.GetString(2), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind), ReadTracks(connection, username, remoteId)));
            }
            using var likedQuery = connection.CreateCommand();
            likedQuery.CommandText = "SELECT uri, title, artist, album, duration_ms, added_at, match_token FROM liked_tracks WHERE username = $username ORDER BY added_at DESC";
            likedQuery.Parameters.AddWithValue("$username", username);
            using var likedReader = likedQuery.ExecuteReader();
            var likedTracks = new List<TrackResponse>();
            while (likedReader.Read())
            {
                likedTracks.Add(new TrackResponse(
                    likedReader.GetString(0),
                    likedReader.GetString(1),
                    likedReader.GetString(2),
                    likedReader.GetString(3),
                    likedReader.IsDBNull(4) ? null : likedReader.GetInt32(4),
                    ParseTimestamp(likedReader.GetString(5)),
                    likedReader.IsDBNull(6) ? null : likedReader.GetString(6)));
            }
            using var presetQuery = connection.CreateCommand();
            presetQuery.CommandText = "SELECT remote_id, name, gains_json, preamp_db, updated_at FROM equalizer_presets WHERE username = $username ORDER BY remote_id";
            presetQuery.Parameters.AddWithValue("$username", username);
            using var presetReader = presetQuery.ExecuteReader();
            var equalizerPresets = new List<EqualizerPresetResponse>();
            while (presetReader.Read())
            {
                equalizerPresets.Add(new EqualizerPresetResponse(
                    presetReader.GetString(0),
                    presetReader.GetString(1),
                    presetReader.GetString(2),
                    presetReader.GetDouble(3),
                    DateTimeOffset.Parse(presetReader.GetString(4), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind)));
            }
            using var deletionQuery = connection.CreateCommand();
            deletionQuery.CommandText = "SELECT entity_type, remote_key, deleted_at FROM sync_tombstones WHERE username = $username ORDER BY entity_type, remote_key";
            deletionQuery.Parameters.AddWithValue("$username", username);
            using var deletionReader = deletionQuery.ExecuteReader();
            var deletions = new List<SyncDeletionResponse>();
            while (deletionReader.Read())
            {
                deletions.Add(new SyncDeletionResponse(
                    deletionReader.GetString(0),
                    deletionReader.GetString(1),
                    ParseTimestamp(deletionReader.GetString(2))));
            }
            return new LibrarySyncResponse(playlists, likedTracks, equalizerPresets, deletions);
        }
    }

    private static string FormatTimestamp(DateTimeOffset value) =>
        value.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);

    private static DateTimeOffset ParseTimestamp(string value) =>
        DateTimeOffset.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);

    private static void UpsertTombstone(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string username,
        string entityType,
        string remoteKey,
        DateTimeOffset deletedAt)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT INTO sync_tombstones(username, entity_type, remote_key, deleted_at)
            VALUES ($username, $entityType, $remoteKey, $deletedAt)
            ON CONFLICT(username, entity_type, remote_key) DO UPDATE SET
                deleted_at = excluded.deleted_at
            WHERE excluded.deleted_at > sync_tombstones.deleted_at;
            """;
        command.Parameters.AddWithValue("$username", username);
        command.Parameters.AddWithValue("$entityType", entityType);
        command.Parameters.AddWithValue("$remoteKey", remoteKey);
        command.Parameters.AddWithValue("$deletedAt", FormatTimestamp(deletedAt));
        command.ExecuteNonQuery();
    }

    private static bool ShouldAcceptChange(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string username,
        string entityType,
        string remoteKey,
        DateTimeOffset updatedAt,
        string table,
        string keyColumn,
        string updatedColumn,
        Func<bool>? acceptEqual = null)
    {
        var deletion = ReadTimestamp(
            connection,
            transaction,
            $"SELECT deleted_at FROM sync_tombstones WHERE username = $username AND entity_type = $entityType AND remote_key = $remoteKey",
            username,
            entityType,
            remoteKey);
        if (deletion is not null && deletion >= updatedAt) return false;

        var current = ReadTimestamp(
            connection,
            transaction,
            $"SELECT {updatedColumn} FROM {table} WHERE username = $username AND {keyColumn} = $remoteKey",
            username,
            entityType: null,
            remoteKey);
        if (current is not null &&
            (current > updatedAt || current == updatedAt && !(acceptEqual?.Invoke() ?? false))) return false;

        if (deletion is not null)
        {
            using var deleteTombstone = connection.CreateCommand();
            deleteTombstone.Transaction = transaction;
            deleteTombstone.CommandText = "DELETE FROM sync_tombstones WHERE username = $username AND entity_type = $entityType AND remote_key = $remoteKey";
            deleteTombstone.Parameters.AddWithValue("$username", username);
            deleteTombstone.Parameters.AddWithValue("$entityType", entityType);
            deleteTombstone.Parameters.AddWithValue("$remoteKey", remoteKey);
            deleteTombstone.ExecuteNonQuery();
        }
        return true;
    }

    private static int CountPlaylistTracks(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string username,
        string remoteId)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT COUNT(*) FROM playlist_tracks WHERE username = $username AND remote_id = $remoteId";
        command.Parameters.AddWithValue("$username", username);
        command.Parameters.AddWithValue("$remoteId", remoteId);
        return Convert.ToInt32(command.ExecuteScalar(), CultureInfo.InvariantCulture);
    }

    private static DateTimeOffset? ReadTimestamp(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string sql,
        string username,
        string? entityType,
        string remoteKey)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        command.Parameters.AddWithValue("$username", username);
        if (entityType is not null) command.Parameters.AddWithValue("$entityType", entityType);
        command.Parameters.AddWithValue("$remoteKey", remoteKey);
        var value = command.ExecuteScalar() as string;
        return value is null ? null : ParseTimestamp(value);
    }

    private static void ApplyTombstones(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string username)
    {
        ApplyTombstonesForEntity(connection, transaction, username,
            SyncEntityTypes.Playlist, "playlists", "remote_id", "updated_at");
        ApplyLikedTrackTombstones(connection, transaction, username);
        ApplyTombstonesForEntity(connection, transaction, username,
            SyncEntityTypes.EqualizerPreset, "equalizer_presets", "remote_id", "updated_at");
    }

    private static void ApplyLikedTrackTombstones(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string username)
    {
        using var discardStaleTombstones = connection.CreateCommand();
        discardStaleTombstones.Transaction = transaction;
        discardStaleTombstones.CommandText = """
            DELETE FROM sync_tombstones
            WHERE username = $username AND entity_type = $entityType
              AND EXISTS (
                SELECT 1 FROM liked_tracks
                WHERE liked_tracks.username = sync_tombstones.username
                  AND (
                    liked_tracks.uri = sync_tombstones.remote_key OR
                    liked_tracks.match_token = sync_tombstones.remote_key
                  )
                  AND liked_tracks.added_at > sync_tombstones.deleted_at
              );
            """;
        discardStaleTombstones.Parameters.AddWithValue("$username", username);
        discardStaleTombstones.Parameters.AddWithValue(
            "$entityType",
            SyncEntityTypes.LikedTrack);
        discardStaleTombstones.ExecuteNonQuery();

        using var deleteEntities = connection.CreateCommand();
        deleteEntities.Transaction = transaction;
        deleteEntities.CommandText = """
            DELETE FROM liked_tracks
            WHERE username = $username
              AND EXISTS (
                SELECT 1 FROM sync_tombstones
                WHERE sync_tombstones.username = liked_tracks.username
                  AND sync_tombstones.entity_type = $entityType
                  AND (
                    sync_tombstones.remote_key = liked_tracks.uri OR
                    sync_tombstones.remote_key = liked_tracks.match_token
                  )
                  AND sync_tombstones.deleted_at >= liked_tracks.added_at
              );
            """;
        deleteEntities.Parameters.AddWithValue("$username", username);
        deleteEntities.Parameters.AddWithValue(
            "$entityType",
            SyncEntityTypes.LikedTrack);
        deleteEntities.ExecuteNonQuery();
    }

    private static void ApplyTombstonesForEntity(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string username,
        string entityType,
        string table,
        string keyColumn,
        string updatedColumn)
    {
        using var discardStaleTombstones = connection.CreateCommand();
        discardStaleTombstones.Transaction = transaction;
        discardStaleTombstones.CommandText = $"""
            DELETE FROM sync_tombstones
            WHERE username = $username AND entity_type = $entityType
              AND EXISTS (
                SELECT 1 FROM {table}
                WHERE {table}.username = sync_tombstones.username
                  AND {table}.{keyColumn} = sync_tombstones.remote_key
                  AND {table}.{updatedColumn} > sync_tombstones.deleted_at
              );
            """;
        discardStaleTombstones.Parameters.AddWithValue("$username", username);
        discardStaleTombstones.Parameters.AddWithValue("$entityType", entityType);
        discardStaleTombstones.ExecuteNonQuery();

        using var deleteEntities = connection.CreateCommand();
        deleteEntities.Transaction = transaction;
        deleteEntities.CommandText = $"""
            DELETE FROM {table}
            WHERE username = $username
              AND EXISTS (
                SELECT 1 FROM sync_tombstones
                WHERE sync_tombstones.username = {table}.username
                  AND sync_tombstones.entity_type = $entityType
                  AND sync_tombstones.remote_key = {table}.{keyColumn}
                  AND sync_tombstones.deleted_at >= {table}.{updatedColumn}
              );
            """;
        deleteEntities.Parameters.AddWithValue("$username", username);
        deleteEntities.Parameters.AddWithValue("$entityType", entityType);
        deleteEntities.ExecuteNonQuery();
    }

    private static IReadOnlyList<TrackResponse> ReadTracks(SqliteConnection connection, string username, string remoteId)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT uri, title, artist, album, duration_ms, match_token FROM playlist_tracks WHERE username = $username AND remote_id = $remoteId ORDER BY rowid";
        command.Parameters.AddWithValue("$username", username);
        command.Parameters.AddWithValue("$remoteId", remoteId);
        using var reader = command.ExecuteReader();
        var tracks = new List<TrackResponse>();
        while (reader.Read())
        {
            tracks.Add(new TrackResponse(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetString(2),
                reader.GetString(3),
                reader.IsDBNull(4) ? null : reader.GetInt32(4),
                MatchToken: reader.IsDBNull(5) ? null : reader.GetString(5)));
        }
        return tracks;
    }
}
