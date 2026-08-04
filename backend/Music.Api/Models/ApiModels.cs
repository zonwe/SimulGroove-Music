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
    IReadOnlyList<TrackRequest>? LikedTracks);

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
    int? DurationMs);

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
    int? DurationMs);

public sealed record LibrarySyncResponse(
    IReadOnlyList<PlaylistResponse> Playlists,
    IReadOnlyList<TrackResponse> LikedTracks);
