import '../database/app_database.dart';

Future<String?> checkTrackAvailability(Track track) async {
  if (!track.isAvailable) return '歌曲已被标记为不可用';
  return null;
}
