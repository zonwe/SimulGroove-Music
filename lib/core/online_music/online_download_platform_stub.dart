import 'online_download_platform.dart';
import 'online_track.dart';

OnlineDownloadPlatform createOnlineDownloadPlatform() =>
    const UnsupportedOnlineDownloadPlatform();

class UnsupportedOnlineDownloadPlatform implements OnlineDownloadPlatform {
  const UnsupportedOnlineDownloadPlatform();

  @override
  bool get supported => false;

  @override
  Future<OnlineDownloadDestination?> chooseDestination() async => null;

  @override
  Future<DownloadedOnlineFile> save({
    required OnlineDownloadDestination destination,
    required OnlineTrack track,
    required OnlinePlaybackSource source,
    required String fileName,
  }) => throw UnsupportedError('当前平台暂不支持下载在线音乐。');
}
