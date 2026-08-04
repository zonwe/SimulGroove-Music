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
                PRIMARY KEY (username, uri)
            );
            """;
        command.ExecuteNonQuery();
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
        IReadOnlyList<TrackRequest> incomingLikedTracks)
    {
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var transaction = connection.BeginTransaction();
            EnsureAccount(connection, transaction, username);
            foreach (var playlist in incomingPlaylists)
            {
                using var playlistCommand = connection.CreateCommand();
                playlistCommand.Transaction = transaction;
                playlistCommand.CommandText = "INSERT INTO playlists(username, remote_id, name, updated_at) VALUES ($username, $remoteId, $name, $updatedAt) ON CONFLICT(username, remote_id) DO UPDATE SET name = excluded.name, updated_at = excluded.updated_at";
                playlistCommand.Parameters.AddWithValue("$username", username);
                playlistCommand.Parameters.AddWithValue("$remoteId", playlist.RemoteId!);
                playlistCommand.Parameters.AddWithValue("$name", playlist.Name!);
                playlistCommand.Parameters.AddWithValue("$updatedAt", (playlist.UpdatedAt ?? DateTimeOffset.UtcNow).ToString("O", CultureInfo.InvariantCulture));
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
                    trackCommand.CommandText = "INSERT INTO playlist_tracks(username, remote_id, uri, title, artist, album, duration_ms) VALUES ($username, $remoteId, $uri, $title, $artist, $album, $durationMs)";
                    trackCommand.Parameters.AddWithValue("$username", username);
                    trackCommand.Parameters.AddWithValue("$remoteId", playlist.RemoteId!);
                    trackCommand.Parameters.AddWithValue("$uri", track.Uri ?? string.Empty);
                    trackCommand.Parameters.AddWithValue("$title", track.Title ?? string.Empty);
                    trackCommand.Parameters.AddWithValue("$artist", track.Artist ?? string.Empty);
                    trackCommand.Parameters.AddWithValue("$album", track.Album ?? string.Empty);
                    trackCommand.Parameters.AddWithValue("$durationMs", (object?)track.DurationMs ?? DBNull.Value);
                    trackCommand.ExecuteNonQuery();
                }
            }
            foreach (var track in incomingLikedTracks)
            {
                if (string.IsNullOrWhiteSpace(track.Uri)) continue;
                using var likedCommand = connection.CreateCommand();
                likedCommand.Transaction = transaction;
                likedCommand.CommandText = """
                    INSERT INTO liked_tracks(username, uri, title, artist, album, duration_ms, added_at)
                    VALUES ($username, $uri, $title, $artist, $album, $durationMs, $addedAt)
                    ON CONFLICT(username, uri) DO UPDATE SET
                        title = excluded.title,
                        artist = excluded.artist,
                        album = excluded.album,
                        duration_ms = excluded.duration_ms;
                    """;
                likedCommand.Parameters.AddWithValue("$username", username);
                likedCommand.Parameters.AddWithValue("$uri", track.Uri);
                likedCommand.Parameters.AddWithValue("$title", track.Title ?? string.Empty);
                likedCommand.Parameters.AddWithValue("$artist", track.Artist ?? string.Empty);
                likedCommand.Parameters.AddWithValue("$album", track.Album ?? string.Empty);
                likedCommand.Parameters.AddWithValue("$durationMs", (object?)track.DurationMs ?? DBNull.Value);
                likedCommand.Parameters.AddWithValue("$addedAt", DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture));
                likedCommand.ExecuteNonQuery();
            }
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
            likedQuery.CommandText = "SELECT uri, title, artist, album, duration_ms FROM liked_tracks WHERE username = $username ORDER BY added_at DESC";
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
                    likedReader.IsDBNull(4) ? null : likedReader.GetInt32(4)));
            }
            return new LibrarySyncResponse(playlists, likedTracks);
        }
    }

    private static IReadOnlyList<TrackResponse> ReadTracks(SqliteConnection connection, string username, string remoteId)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT uri, title, artist, album, duration_ms FROM playlist_tracks WHERE username = $username AND remote_id = $remoteId ORDER BY rowid";
        command.Parameters.AddWithValue("$username", username);
        command.Parameters.AddWithValue("$remoteId", remoteId);
        using var reader = command.ExecuteReader();
        var tracks = new List<TrackResponse>();
        while (reader.Read())
        {
            tracks.Add(new TrackResponse(reader.GetString(0), reader.GetString(1), reader.GetString(2), reader.GetString(3), reader.IsDBNull(4) ? null : reader.GetInt32(4)));
        }
        return tracks;
    }
}
