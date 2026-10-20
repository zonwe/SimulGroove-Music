namespace Music.Api.Services.OnlineMusic;

/// <summary>
/// sidecar 调用的规范操作名。
///
/// 这些值同时用于指标标签和熔断分桶，因此必须保持低基数：只能是下面的常量，
/// 绝不能包含搜索词、来源、曲目 ID、账号、Token 或 URL。
/// </summary>
public static class OnlineMusicOperations
{
    public const string Search = "search";
    public const string Resolve = "resolve";
    public const string Stream = "stream";
    public const string Lyrics = "lyrics";
    public const string Artwork = "artwork";
    public const string Download = "download";
    public const string Other = "other";

    /// <summary>
    /// 把 sidecar 请求路径归一到规范操作名。识别不出来时返回 <see cref="Other"/>，
    /// 这样新增端点也不会把高基数路径写进标签。
    /// </summary>
    public static string FromPath(string? path)
    {
        if (path is null) return Other;
        if (path.EndsWith("/search", StringComparison.Ordinal)) return Search;
        if (path.EndsWith("/resolve", StringComparison.Ordinal)) return Resolve;
        if (path.Contains("/streams/", StringComparison.Ordinal)) return Stream;
        if (path.EndsWith("/lyrics", StringComparison.Ordinal)) return Lyrics;
        if (path.EndsWith("/cover", StringComparison.Ordinal)) return Artwork;
        if (path.EndsWith("/download", StringComparison.Ordinal)) return Download;
        return Other;
    }
}
