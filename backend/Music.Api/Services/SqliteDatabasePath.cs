using Microsoft.Data.Sqlite;

namespace Music.Api.Services;

/// <summary>
/// 解析 Database:Path 为绝对路径（相对路径基于 ContentRoot），
/// 并确保其所在目录存在。SQLite 相关组件应共用此逻辑，
/// 避免各自拼接出不同的数据库文件。
/// </summary>
public static class SqliteDatabasePath
{
    public static string Resolve(IConfiguration configuration, IHostEnvironment environment)
    {
        var configuredPath = configuration["Database:Path"] ?? "storage/music.db";
        var databasePath = Path.IsPathRooted(configuredPath)
            ? configuredPath
            : Path.GetFullPath(Path.Combine(environment.ContentRootPath, configuredPath));
        var directory = Path.GetDirectoryName(databasePath);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        return databasePath;
    }

    public static string ToConnectionString(string databasePath) =>
        new SqliteConnectionStringBuilder { DataSource = databasePath }.ToString();
}
