using System.Globalization;
using Microsoft.Data.Sqlite;

namespace Music.Api.Services;

/// <summary>
/// refresh_tokens 表的持久化边界。
///
/// 方法接收调用方打开的连接与事务，保证 Refresh Token 的写入与账号读取、
/// Access Token 签发在同一事务内完成；不要在 Store 内部另开连接。
/// Store 只存储与查询令牌哈希，令牌原文与哈希计算属于 AuthService。
/// </summary>
public interface IRefreshTokenStore
{
    /// <summary>创建 refresh_tokens 表与索引（幂等）。</summary>
    void Initialize(SqliteConnection connection);

    void Insert(
        SqliteConnection connection,
        SqliteTransaction transaction,
        RefreshTokenRow token);

    StoredRefreshToken? Find(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string tokenHash);

    /// <summary>轮换：撤销旧令牌并记录其替换者的哈希。</summary>
    void MarkReplaced(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string tokenHash,
        string replacedByHash,
        DateTimeOffset revokedAt);

    /// <summary>撤销用户全部未撤销的令牌（重复使用检测后的止损动作）。</summary>
    void RevokeAllForUser(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string username,
        DateTimeOffset revokedAt);
}

public sealed record RefreshTokenRow(
    string TokenHash,
    string Username,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt);

public sealed record StoredRefreshToken(
    string Username,
    DateTimeOffset ExpiresAt,
    bool Revoked);

public sealed class SqliteRefreshTokenStore : IRefreshTokenStore
{
    public void Initialize(SqliteConnection connection)
    {
        using var command = connection.CreateCommand();
        command.CommandText = """
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
    }

    public void Insert(
        SqliteConnection connection,
        SqliteTransaction transaction,
        RefreshTokenRow token)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "INSERT INTO refresh_tokens(token_hash, username, expires_at, created_at, revoked_at, replaced_by_hash) VALUES ($hash, $username, $expiresAt, $createdAt, NULL, NULL)";
        command.Parameters.AddWithValue("$hash", token.TokenHash);
        command.Parameters.AddWithValue("$username", token.Username);
        command.Parameters.AddWithValue("$expiresAt", FormatDate(token.ExpiresAt));
        command.Parameters.AddWithValue("$createdAt", FormatDate(token.CreatedAt));
        command.ExecuteNonQuery();
    }

    public StoredRefreshToken? Find(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string tokenHash)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT username, expires_at, revoked_at FROM refresh_tokens WHERE token_hash = $hash";
        command.Parameters.AddWithValue("$hash", tokenHash);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return null;

        return new StoredRefreshToken(
            reader.GetString(0),
            ParseDate(reader.GetString(1)),
            !reader.IsDBNull(2));
    }

    public void MarkReplaced(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string tokenHash,
        string replacedByHash,
        DateTimeOffset revokedAt)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "UPDATE refresh_tokens SET revoked_at = $revokedAt, replaced_by_hash = $replacement WHERE token_hash = $hash";
        command.Parameters.AddWithValue("$revokedAt", FormatDate(revokedAt));
        command.Parameters.AddWithValue("$replacement", replacedByHash);
        command.Parameters.AddWithValue("$hash", tokenHash);
        command.ExecuteNonQuery();
    }

    public void RevokeAllForUser(
        SqliteConnection connection,
        SqliteTransaction transaction,
        string username,
        DateTimeOffset revokedAt)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "UPDATE refresh_tokens SET revoked_at = $revokedAt WHERE username = $username AND revoked_at IS NULL";
        command.Parameters.AddWithValue("$revokedAt", FormatDate(revokedAt));
        command.Parameters.AddWithValue("$username", username);
        command.ExecuteNonQuery();
    }

    private static string FormatDate(DateTimeOffset value) =>
        value.ToString("O", CultureInfo.InvariantCulture);

    private static DateTimeOffset ParseDate(string value) =>
        DateTimeOffset.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
}
