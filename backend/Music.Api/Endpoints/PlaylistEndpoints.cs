using Music.Api.Data;
using Music.Api.Models;
using Music.Api.Services;

namespace Music.Api.Endpoints;

public static class PlaylistEndpoints
{
	public static IEndpointRouteBuilder MapPlaylistEndpoints(this IEndpointRouteBuilder endpoints)
	{
		endpoints.MapPost("/api/playlists/sync",
			async (SyncPlaylistsRequest request, HttpRequest httpRequest, IPlaylistStore playlists, IAuthService auth) =>
			{
				var account = auth.Authenticate(httpRequest.ReadBearerToken());
				if (account is null) return Results.Unauthorized();

				var incoming = request.Playlists ?? [];
				var likedTracks = request.LikedTracks ?? [];
				var equalizerPresets = request.EqualizerPresets ?? [];
				var deletions = request.Deletions ?? [];
				if (incoming.Any(playlist => string.IsNullOrWhiteSpace(playlist.RemoteId) || string.IsNullOrWhiteSpace(playlist.Name)))
				{
					return Results.BadRequest(new ProblemResponse("invalid_playlist", "Every playlist requires remoteId and name."));
				}
				if (incoming.SelectMany(playlist => playlist.Tracks ?? [])
						.Concat(likedTracks)
						.Any(track => !TrackMatchTokens.IsValidOrEmpty(track.MatchToken)))
				{
					return Results.BadRequest(new ProblemResponse(
						"invalid_track_match_token",
						"Track match tokens must use the hmac-sha256 format."));
				}
				if (equalizerPresets.Any(preset => string.IsNullOrWhiteSpace(preset.RemoteId) || string.IsNullOrWhiteSpace(preset.Name)))
				{
					return Results.BadRequest(new ProblemResponse("invalid_preset", "Every equalizer preset requires remoteId and name."));
				}
				if (deletions.Any(deletion =>
					string.IsNullOrWhiteSpace(deletion.EntityType) ||
					!SyncEntityTypes.IsSupported(deletion.EntityType) ||
					string.IsNullOrWhiteSpace(deletion.RemoteKey) ||
					(deletion.EntityType == SyncEntityTypes.LikedTrack &&
						deletion.RemoteKey.StartsWith(TrackMatchTokens.Prefix, StringComparison.Ordinal) &&
						!TrackMatchTokens.IsValidOrEmpty(deletion.RemoteKey)) ||
					deletion.DeletedAt is null))
				{
					return Results.BadRequest(new ProblemResponse("invalid_deletion", "Every deletion requires entityType, remoteKey and deletedAt."));
				}
				return Results.Ok(playlists.SyncLibrary(account.Username, incoming, likedTracks, equalizerPresets, deletions));
			});


		return endpoints;
	}
}
