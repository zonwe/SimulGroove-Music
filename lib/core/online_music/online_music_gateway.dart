import '../auth/backend_gateway.dart';
import 'online_track.dart';

abstract interface class OnlineMusicGateway {
  Future<OnlineMusicSearchResult> search(
    BackendSession session, {
    required String query,
    List<String> sources = const [],
    int limit = 20,
    String? cursor,
  });

  Future<OnlinePlaybackSource> requestPlayback(
    BackendSession session,
    OnlineTrack track,
  );
}
