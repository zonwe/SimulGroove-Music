using Music.Api.Models;

namespace Music.Api.Data;

public interface IPlaylistStore
{
    LibrarySyncResponse SyncLibrary(
        string username,
        IReadOnlyList<PlaylistRequest> incomingPlaylists,
        IReadOnlyList<TrackRequest> incomingLikedTracks,
        IReadOnlyList<EqualizerPresetRequest> incomingEqualizerPresets);
}

