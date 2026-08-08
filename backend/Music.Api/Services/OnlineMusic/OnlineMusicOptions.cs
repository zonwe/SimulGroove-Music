namespace Music.Api.Services.OnlineMusic;

public sealed class OnlineMusicOptions
{
    public const string SectionName = "OnlineMusic";

    public bool Enabled { get; init; }
    public string SidecarBaseUrl { get; init; } = "http://127.0.0.1:8081";
    public int RequestTimeoutSeconds { get; init; } = 12;
    public int SearchCacheSeconds { get; init; } = 60;
    public int RequestsPerMinute { get; init; } = 30;
    public int MaxResults { get; init; } = 50;
    public int PlaybackTicketSeconds { get; init; } = 300;
    public IReadOnlyList<string> AllowedSources { get; init; } = [];
}
