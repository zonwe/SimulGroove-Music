namespace Music.Api.Services.OnlineMusic;

public sealed class OnlineMusicOptions
{
    public const string SectionName = "OnlineMusic";

    public bool Enabled { get; init; }
    public string SidecarBaseUrl { get; init; } = "http://127.0.0.1:8080";
    public int RequestTimeoutSeconds { get; init; } = 12;
    public int SearchCacheSeconds { get; init; } = 60;
    public int RequestsPerMinute { get; init; } = 30;
    public int MaxResults { get; init; } = 50;
    public int PlaybackTicketSeconds { get; init; } = 300;
    public int LyricsCacheSeconds { get; init; } = 900;
    public int ArtworkCacheSeconds { get; init; } = 21600;
    public int AssetCacheSizeBytes { get; init; } = 32 * 1024 * 1024;
    public int MaxLyricsBytes { get; init; } = 512 * 1024;
    public int MaxArtworkBytes { get; init; } = 2 * 1024 * 1024;
    public IReadOnlyList<string> AllowedSources { get; init; } = [];
}
