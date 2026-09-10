namespace Music.Api.Models;

public sealed record LoginRequest(string? Username, string? Password);

public sealed record AccountResponse(
    string RemoteId,
    string Username,
    string DisplayName,
    string? AvatarUri);

public sealed record SessionAccountResponse(AccountResponse Account);

public sealed record ProblemResponse(string Code, string Message);

public sealed record SyncPlaylistsRequest(
    IReadOnlyList<PlaylistRequest>? Playlists,
    IReadOnlyList<TrackRequest>? LikedTracks,
    IReadOnlyList<EqualizerPresetRequest>? EqualizerPresets,
    IReadOnlyList<SyncDeletionRequest>? Deletions);

public sealed record PlaylistRequest(
    string? RemoteId,
    string? Name,
    DateTimeOffset? UpdatedAt,
    IReadOnlyList<TrackRequest>? Tracks);

public sealed record TrackRequest(
    string? Uri,
    string? Title,
    string? Artist,
    string? Album,
    int? DurationMs,
    DateTimeOffset? UpdatedAt = null,
    string? MatchToken = null);

public static class TrackMatchTokens
{
    public const string Prefix = "hmac-sha256:";
    public const int Length = 76;

    public static bool IsValidOrEmpty(string? value)
    {
        if (string.IsNullOrEmpty(value)) return true;
        if (value.Length != Length ||
            !value.StartsWith(Prefix, StringComparison.Ordinal)) return false;
        foreach (var character in value.AsSpan(Prefix.Length))
        {
            if (character is not (>= '0' and <= '9') and
                not (>= 'a' and <= 'f')) return false;
        }
        return true;
    }
}

public sealed record SyncDeletionRequest(
    string? EntityType,
    string? RemoteKey,
    DateTimeOffset? DeletedAt);

public static class SyncEntityTypes
{
    public const string Playlist = "playlist";
    public const string LikedTrack = "likedTrack";
    public const string EqualizerPreset = "equalizerPreset";

    public static bool IsSupported(string? value) =>
        value is Playlist or LikedTrack or EqualizerPreset;
}


public sealed record EqualizerPresetRequest(
    string? RemoteId,
    string? Name,
    string? GainsJson,
    double? PreampDb,
    DateTimeOffset? UpdatedAt);

public sealed record PlaylistResponse(
    string RemoteId,
    string Name,
    DateTimeOffset UpdatedAt,
    IReadOnlyList<TrackResponse> Tracks);

public sealed record TrackResponse(
    string Uri,
    string Title,
    string Artist,
    string Album,
    int? DurationMs,
    DateTimeOffset? UpdatedAt = null,
    string? MatchToken = null);

public sealed record SyncDeletionResponse(
    string EntityType,
    string RemoteKey,
    DateTimeOffset DeletedAt);

public sealed record EqualizerPresetResponse(
    string RemoteId,
    string Name,
    string GainsJson,
    double PreampDb,
    DateTimeOffset UpdatedAt);

public sealed record LibrarySyncResponse(
    IReadOnlyList<PlaylistResponse> Playlists,
    IReadOnlyList<TrackResponse> LikedTracks,
    IReadOnlyList<EqualizerPresetResponse> EqualizerPresets,
    IReadOnlyList<SyncDeletionResponse> Deletions);

