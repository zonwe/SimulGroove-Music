using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using Music.Api.Models;

namespace Music.Api.Services;

public sealed record AuthTokenResponse(
    string Token,
    string RefreshToken,
    DateTimeOffset ExpiresAt,
    AccountResponse Account);

public sealed record RefreshTokenRequest(string? RefreshToken);

public sealed class AuthService : IAuthService
{
    private const int PasswordIterations = 210_000;
    private const int PasswordSaltBytes = 16;
    private const int PasswordHashBytes = 32;

    private readonly object _gate = new();
    private readonly string _connectionString;
    private readonly JwtTokenService _jwt;
    private readonly TimeSpan _refreshLifetime;

    public AuthService(IConfiguration configuration, IHostEnvironment environment)
    {
        var configuredPath = configuration["Database:Path"] ?? "storage/music.db";
        var databasePath = Path.IsPathRooted(configuredPath)
            ? configuredPath
            : Path.GetFullPath(Path.Combine(environment.ContentRootPath, configuredPath));
        var directory = Path.GetDirectoryName(databasePath);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);

        _connectionString = new SqliteConnectionStringBuilder { DataSource = databasePath }.ToString();
        _jwt = new JwtTokenService(configuration);
        _refreshLifetime = TimeSpan.FromDays(configuration.GetValue("Auth:RefreshTokenDays", 30));
        Initialize();
    }

    public AuthTokenResponse? SignIn(string username, string password)
    {
        var normalized = username.Trim().ToLowerInvariant();
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var transaction = connection.BeginTransaction();
            var stored = ReadPassword(connection, transaction, normalized);
            if (stored is null)
            {
                var salt = RandomNumberGenerator.GetBytes(PasswordSaltBytes);
                var hash = HashPassword(password, salt, PasswordIterations);
                using var insert = connection.CreateCommand();
                insert.Transaction = transaction;
                insert.CommandText = "INSERT INTO accounts(username, remote_id, display_name, avatar_uri, password_hash, password_salt, password_iterations) VALUES ($username, $remoteId, $displayName, NULL, $hash, $salt, $iterations)";
                insert.Parameters.AddWithValue("$username", normalized);
                insert.Parameters.AddWithValue("$remoteId", $"account-{normalized}");
                insert.Parameters.AddWithValue("$displayName", normalized.Split('@')[0]);
                insert.Parameters.AddWithValue("$hash", Convert.ToBase64String(hash));
                insert.Parameters.AddWithValue("$salt", Convert.ToBase64String(salt));
                insert.Parameters.AddWithValue("$iterations", PasswordIterations);
                insert.ExecuteNonQuery();
            }
            else if (stored.Value.Hash is null || stored.Value.Salt is null)
            {
                SetInitialPassword(connection, transaction, normalized, password);
            }
            else
            {
                var actual = HashPassword(password, Convert.FromBase64String(stored.Value.Salt), stored.Value.Iterations);
                if (!CryptographicOperations.FixedTimeEquals(actual, Convert.FromBase64String(stored.Value.Hash)))
                {
                    transaction.Rollback();
                    return null;
                }
            }

            var account = ReadAccount(connection, transaction, normalized)!;
            var response = IssueTokens(connection, transaction, account);
            transaction.Commit();
            return response;
        }
    }

    public AuthTokenResponse? Refresh(string refreshToken)
    {
        var tokenHash = HashRefreshToken(refreshToken);
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var transaction = connection.BeginTransaction();
            using var query = connection.CreateCommand();
            query.Transaction = transaction;
            query.CommandText = "SELECT username, expires_at, revoked_at FROM refresh_tokens WHERE token_hash = $hash";
            query.Parameters.AddWithValue("$hash", tokenHash);
            using var reader = query.ExecuteReader();
            if (!reader.Read()) return null;

            var username = reader.GetString(0);
            var expiresAt = ParseDate(reader.GetString(1));
            var revoked = !reader.IsDBNull(2);
            reader.Close();

            if (revoked || expiresAt <= DateTimeOffset.UtcNow)
            {
                if (revoked) RevokeAll(connection, transaction, username);
                transaction.Commit();
                return null;
            }

            var account = ReadAccount(connection, transaction, username);
            if (account is null) return null;
            var response = IssueTokens(connection, transaction, account);
            using var revoke = connection.CreateCommand();
            revoke.Transaction = transaction;
            revoke.CommandText = "UPDATE refresh_tokens SET revoked_at = $revokedAt, replaced_by_hash = $replacement WHERE token_hash = $hash";
            revoke.Parameters.AddWithValue("$revokedAt", DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture));
            revoke.Parameters.AddWithValue("$replacement", HashRefreshToken(response.RefreshToken));
            revoke.Parameters.AddWithValue("$hash", tokenHash);
            revoke.ExecuteNonQuery();
            transaction.Commit();
            return response;
        }
    }

    public AccountResponse? Authenticate(string? accessToken)
    {
        if (string.IsNullOrWhiteSpace(accessToken)) return null;
        var username = _jwt.Validate(accessToken);
        if (username is null) return null;
        lock (_gate)
        {
            using var connection = OpenConnection();
            return ReadAccount(connection, null, username);
        }
    }

    public bool RevokeAll(string accessToken)
    {
        var username = _jwt.Validate(accessToken);
        if (username is null) return false;
        lock (_gate)
        {
            using var connection = OpenConnection();
            using var transaction = connection.BeginTransaction();
            RevokeAll(connection, transaction, username);
            transaction.Commit();
            return true;
        }
    }

    private AuthTokenResponse IssueTokens(SqliteConnection connection, SqliteTransaction transaction, AccountResponse account)
    {
        var access = _jwt.Issue(account.Username);
        var refreshToken = Base64Url(RandomNumberGenerator.GetBytes(64));
        var refreshExpiresAt = DateTimeOffset.UtcNow.Add(_refreshLifetime);
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "INSERT INTO refresh_tokens(token_hash, username, expires_at, created_at, revoked_at, replaced_by_hash) VALUES ($hash, $username, $expiresAt, $createdAt, NULL, NULL)";
        command.Parameters.AddWithValue("$hash", HashRefreshToken(refreshToken));
        command.Parameters.AddWithValue("$username", account.Username);
        command.Parameters.AddWithValue("$expiresAt", refreshExpiresAt.ToString("O", CultureInfo.InvariantCulture));
        command.Parameters.AddWithValue("$createdAt", DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture));
        command.ExecuteNonQuery();
        return new AuthTokenResponse(access.Token, refreshToken, access.ExpiresAt, account);
    }

    private void Initialize()
    {
        using var connection = OpenConnection();
        using var command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA journal_mode = WAL;
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS accounts (
                username TEXT PRIMARY KEY,
                remote_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                avatar_uri TEXT NULL,
                password_hash TEXT NULL,
                password_salt TEXT NULL,
                password_iterations INTEGER NULL
            );
            CREATE TABLE IF NOT EXISTS refresh_tokens (
                token_hash TEXT PRIMARY KEY,
                username TEXT NOT NULL REFERENCES accounts(username) ON DELETE CASCADE,
                expires_at TEXT NOT NULL,
                created_at TEXT NOT NULL,
                revoked_at TEXT NULL,
                replaced_by_hash TEXT NULL
            );
            CREATE INDEX IF NOT EXISTS ix_refresh_tokens_username ON refresh_tokens(username);
            """;
        command.ExecuteNonQuery();
        EnsureColumn(connection, "accounts", "password_hash", "TEXT NULL");
        EnsureColumn(connection, "accounts", "password_salt", "TEXT NULL");
        EnsureColumn(connection, "accounts", "password_iterations", "INTEGER NULL");
    }

    private static void EnsureColumn(SqliteConnection connection, string table, string column, string definition)
    {
        using var check = connection.CreateCommand();
        check.CommandText = $"PRAGMA table_info({table})";
        using var reader = check.ExecuteReader();
        while (reader.Read())
        {
            if (string.Equals(reader.GetString(1), column, StringComparison.OrdinalIgnoreCase)) return;
        }
        reader.Close();
        using var alter = connection.CreateCommand();
        alter.CommandText = $"ALTER TABLE {table} ADD COLUMN {column} {definition}";
        alter.ExecuteNonQuery();
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

    private static (string? Hash, string? Salt, int Iterations)? ReadPassword(SqliteConnection connection, SqliteTransaction transaction, string username)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT password_hash, password_salt, password_iterations FROM accounts WHERE username = $username";
        command.Parameters.AddWithValue("$username", username);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return null;
        return (
            reader.IsDBNull(0) ? null : reader.GetString(0),
            reader.IsDBNull(1) ? null : reader.GetString(1),
            reader.IsDBNull(2) ? PasswordIterations : reader.GetInt32(2));
    }

    private static AccountResponse? ReadAccount(SqliteConnection connection, SqliteTransaction? transaction, string username)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT remote_id, username, display_name, avatar_uri FROM accounts WHERE username = $username";
        command.Parameters.AddWithValue("$username", username);
        using var reader = command.ExecuteReader();
        return reader.Read()
            ? new AccountResponse(reader.GetString(0), reader.GetString(1), reader.GetString(2), reader.IsDBNull(3) ? null : reader.GetString(3))
            : null;
    }

    private static void SetInitialPassword(SqliteConnection connection, SqliteTransaction transaction, string username, string password)
    {
        var salt = RandomNumberGenerator.GetBytes(PasswordSaltBytes);
        var hash = HashPassword(password, salt, PasswordIterations);
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "UPDATE accounts SET password_hash = $hash, password_salt = $salt, password_iterations = $iterations WHERE username = $username";
        command.Parameters.AddWithValue("$hash", Convert.ToBase64String(hash));
        command.Parameters.AddWithValue("$salt", Convert.ToBase64String(salt));
        command.Parameters.AddWithValue("$iterations", PasswordIterations);
        command.Parameters.AddWithValue("$username", username);
        command.ExecuteNonQuery();
    }

    private static byte[] HashPassword(string password, byte[] salt, int iterations) =>
        Rfc2898DeriveBytes.Pbkdf2(password, salt, iterations, HashAlgorithmName.SHA256, PasswordHashBytes);

    private static string HashRefreshToken(string token) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    private static void RevokeAll(SqliteConnection connection, SqliteTransaction transaction, string username)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "UPDATE refresh_tokens SET revoked_at = $revokedAt WHERE username = $username AND revoked_at IS NULL";
        command.Parameters.AddWithValue("$revokedAt", DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture));
        command.Parameters.AddWithValue("$username", username);
        command.ExecuteNonQuery();
    }

    private static DateTimeOffset ParseDate(string value) =>
        DateTimeOffset.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}

public sealed class JwtTokenService
{
    private readonly byte[] _key;
    private readonly string _issuer;
    private readonly string _audience;
    private readonly TimeSpan _accessLifetime;

    public JwtTokenService(IConfiguration configuration)
    {
        var key = configuration["Auth:JwtKey"] ?? throw new InvalidOperationException("Auth:JwtKey 未配置。 ");
        if (Encoding.UTF8.GetByteCount(key) < 32) throw new InvalidOperationException("Auth:JwtKey 至少需要 32 字节。 ");
        _key = Encoding.UTF8.GetBytes(key);
        _issuer = configuration["Auth:Issuer"] ?? "flutter-music-api";
        _audience = configuration["Auth:Audience"] ?? "flutter-music-client";
        _accessLifetime = TimeSpan.FromMinutes(configuration.GetValue("Auth:AccessTokenMinutes", 15));
    }

    public (string Token, DateTimeOffset ExpiresAt) Issue(string username)
    {
        var now = DateTimeOffset.UtcNow;
        var expiresAt = now.Add(_accessLifetime);
        var header = Base64Url(JsonSerializer.SerializeToUtf8Bytes(new { alg = "HS256", typ = "JWT" }));
        var payload = Base64Url(JsonSerializer.SerializeToUtf8Bytes(new
        {
            sub = username,
            jti = Guid.NewGuid().ToString("N"),
            iss = _issuer,
            aud = _audience,
            iat = now.ToUnixTimeSeconds(),
            exp = expiresAt.ToUnixTimeSeconds()
        }));
        var unsigned = $"{header}.{payload}";
        var signature = Base64Url(HMACSHA256.HashData(_key, Encoding.ASCII.GetBytes(unsigned)));
        return ($"{unsigned}.{signature}", expiresAt);
    }

    public string? Validate(string token)
    {
        var parts = token.Split('.');
        if (parts.Length != 3) return null;
        try
        {
            using var header = JsonDocument.Parse(Base64UrlDecode(parts[0]));
            if (header.RootElement.GetProperty("alg").GetString() != "HS256" ||
                header.RootElement.GetProperty("typ").GetString() != "JWT") return null;

            var unsigned = $"{parts[0]}.{parts[1]}";
            var expected = HMACSHA256.HashData(_key, Encoding.ASCII.GetBytes(unsigned));
            var actual = Base64UrlDecode(parts[2]);
            if (!CryptographicOperations.FixedTimeEquals(expected, actual)) return null;

            using var payload = JsonDocument.Parse(Base64UrlDecode(parts[1]));
            var root = payload.RootElement;
            if (root.GetProperty("iss").GetString() != _issuer || root.GetProperty("aud").GetString() != _audience) return null;
            if (root.GetProperty("exp").GetInt64() <= DateTimeOffset.UtcNow.ToUnixTimeSeconds()) return null;
            return root.GetProperty("sub").GetString();
        }
        catch (Exception exception) when (exception is FormatException or JsonException or KeyNotFoundException or InvalidOperationException)
        {
            return null;
        }
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded += (padded.Length % 4) switch { 2 => "==", 3 => "=", _ => string.Empty };
        return Convert.FromBase64String(padded);
    }
}
