using Microsoft.Data.Sqlite;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Services;

namespace Music.Api.Tests;

[TestClass]
public sealed class RefreshTokenStoreTests
{
    private TestDirectory _directory = null!;
    private SqliteConnection _connection = null!;
    private SqliteRefreshTokenStore _store = null!;

    [TestInitialize]
    public void SetUp()
    {
        _directory = new TestDirectory();
        _connection = new SqliteConnection(
            SqliteDatabasePath.ToConnectionString(
                Path.Combine(_directory.Path, "music.db")));
        _connection.Open();

        // 与 AuthService 相同的宿主约束：外键开启，令牌行引用账号。
        using (var pragma = _connection.CreateCommand())
        {
            pragma.CommandText = "PRAGMA foreign_keys = ON";
            pragma.ExecuteNonQuery();
        }
        using (var accounts = _connection.CreateCommand())
        {
            accounts.CommandText = """
                CREATE TABLE IF NOT EXISTS accounts (
                    username TEXT PRIMARY KEY,
                    remote_id TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    avatar_uri TEXT NULL,
                    password_hash TEXT NULL,
                    password_salt TEXT NULL,
                    password_iterations INTEGER NULL
                );
                INSERT INTO accounts(username, remote_id, display_name) VALUES
                    ('alice@example.com', 'account-alice', 'alice'),
                    ('bob@example.com', 'account-bob', 'bob');
                """;
            accounts.ExecuteNonQuery();
        }

        _store = new SqliteRefreshTokenStore();
        _store.Initialize(_connection);
    }

    [TestCleanup]
    public void TearDown()
    {
        _connection.Dispose();
        SqliteConnection.ClearAllPools();
        _directory.Dispose();
    }

    [TestMethod]
    public void InitializeIsIdempotentAndCreatesTableWithIndex()
    {
        // SetUp 已调用一次；重复建表不应抛错。
        _store.Initialize(_connection);

        var names = new List<string>();
        using (var query = _connection.CreateCommand())
        {
            query.CommandText = "SELECT name FROM sqlite_master WHERE type IN ('table', 'index') AND name LIKE '%refresh_tokens%'";
            using var reader = query.ExecuteReader();
            while (reader.Read()) names.Add(reader.GetString(0));
        }

        CollectionAssert.Contains(names, "refresh_tokens");
        CollectionAssert.Contains(names, "ix_refresh_tokens_username");
    }

    [TestMethod]
    public void InsertAndFindRoundTripTokenState()
    {
        var expiresAt = DateTimeOffset.UtcNow.AddDays(30);
        using var transaction = _connection.BeginTransaction();
        _store.Insert(
            _connection,
            transaction,
            new RefreshTokenRow("hash-active", "alice@example.com", DateTimeOffset.UtcNow, expiresAt));

        var stored = _store.Find(_connection, transaction, "hash-active");
        Assert.IsNotNull(stored);
        Assert.AreEqual("alice@example.com", stored.Username);
        Assert.AreEqual(expiresAt.ToUnixTimeMilliseconds(), stored.ExpiresAt.ToUnixTimeMilliseconds());
        Assert.IsFalse(stored.Revoked);

        Assert.IsNull(_store.Find(_connection, transaction, "hash-unknown"));
        transaction.Commit();
    }

    [TestMethod]
    public void MarkReplacedRevokesOldTokenAndRecordsReplacement()
    {
        using var transaction = _connection.BeginTransaction();
        _store.Insert(
            _connection,
            transaction,
            new RefreshTokenRow("hash-old", "alice@example.com", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddDays(30)));
        _store.Insert(
            _connection,
            transaction,
            new RefreshTokenRow("hash-new", "alice@example.com", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddDays(30)));

        var revokedAt = DateTimeOffset.UtcNow;
        _store.MarkReplaced(_connection, transaction, "hash-old", "hash-new", revokedAt);

        var oldToken = _store.Find(_connection, transaction, "hash-old");
        Assert.IsNotNull(oldToken);
        Assert.IsTrue(oldToken.Revoked);

        using var query = _connection.CreateCommand();
        query.Transaction = transaction;
        query.CommandText = "SELECT replaced_by_hash FROM refresh_tokens WHERE token_hash = 'hash-old'";
        Assert.AreEqual("hash-new", query.ExecuteScalar());
        transaction.Commit();
    }

    [TestMethod]
    public void RevokeAllForUserOnlyAffectsTargetUser()
    {
        using var transaction = _connection.BeginTransaction();
        foreach (var hash in new[] { "hash-a1", "hash-a2" })
        {
            _store.Insert(
                _connection,
                transaction,
                new RefreshTokenRow(hash, "alice@example.com", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddDays(30)));
        }
        _store.Insert(
            _connection,
            transaction,
            new RefreshTokenRow("hash-b1", "bob@example.com", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddDays(30)));

        _store.RevokeAllForUser(_connection, transaction, "alice@example.com", DateTimeOffset.UtcNow);

        Assert.IsTrue(_store.Find(_connection, transaction, "hash-a1")!.Revoked);
        Assert.IsTrue(_store.Find(_connection, transaction, "hash-a2")!.Revoked);
        Assert.IsFalse(_store.Find(_connection, transaction, "hash-b1")!.Revoked);

        // 重复执行只影响仍处活跃状态的令牌，不覆盖已有撤销时间。
        _store.RevokeAllForUser(_connection, transaction, "alice@example.com", DateTimeOffset.UtcNow);
        Assert.IsFalse(_store.Find(_connection, transaction, "hash-b1")!.Revoked);
        transaction.Commit();
    }
}
