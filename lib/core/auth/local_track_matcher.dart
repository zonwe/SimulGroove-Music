import '../database/app_database.dart';
import 'backend_gateway.dart';
import 'track_match_token.dart';

/// `online-music://track/{provider}/{id}` 在本机音乐库中的稳定 id。
String onlineMusicTrackId(Uri uri) =>
    'online:${uri.pathSegments[0]}:${uri.pathSegments[1]}';

bool isOnlineMusicTrackUri(Uri? uri) =>
    uri != null &&
    uri.scheme == 'online-music' &&
    uri.host == 'track' &&
    uri.pathSegments.length == 2;

/// 只有这些来源的曲目参与标题/文件名兜底匹配。
///
/// 在线占位行没有本地文件，参与元数据匹配只会制造歧义；新增扫描来源时需要
/// 在这里显式登记，否则该来源的曲目只能靠 URI 或盲匹配令牌命中。
const _indexedLocalSourceTypes = {
  'windows_file',
  'linux_file',
  'android_media_store',
  'android_document_tree',
};

/// 把远端歌单/喜欢里的曲目解析成本机已索引的曲目。
///
/// 远端只保存可搬运的描述（uri、标题、艺术家、专辑、时长）和账号绑定的盲
/// 匹配令牌；本机身份（[Track.id]、`content://` 与 `file://` URI）无法跨设备
/// 复用，所以按以下顺序匹配，命中即返回：
///
/// 1. URI 完全相同：同机重登，或 Android MediaStore id 未变化；
/// 2. 在线曲目按 `online:{provider}:{id}` 稳定 id；
/// 3. 盲匹配令牌唯一命中：文件字节一致即可，与路径、标签无关；
/// 4. 标题/文件名/艺术家/专辑/时长打分，最高分必须唯一，否则视为歧义。
class LocalTrackMatcher {
  LocalTrackMatcher(Iterable<Track> tracks, {required this.trackMatchKey}) {
    for (final track in tracks) {
      _knownByUri[track.uri] = track;
      final matchToken = matchTokenFor(track);
      if (matchToken != null) {
        _knownTracksByMatchToken.putIfAbsent(matchToken, () => []).add(track);
      }
      if (!track.isAvailable) continue;
      _availableByUri[track.uri] = track;
      _availableById[track.id] = track;
      if (matchToken != null) {
        _tracksByMatchToken.putIfAbsent(matchToken, () => []).add(track);
      }
      if (!_indexedLocalSourceTypes.contains(track.sourceType)) continue;
      final title = _normalizeSyncValue(track.title);
      if (title.isNotEmpty) {
        _tracksByTitle.putIfAbsent(title, () => []).add(track);
      }
      final fileName = _localTrackFileName(track);
      if (fileName.isNotEmpty) {
        _tracksByFileName.putIfAbsent(fileName, () => []).add(track);
      }
    }
  }

  final Map<String, Track> _availableByUri = {};
  final Map<String, Track> _availableById = {};
  final Map<String, Track> _knownByUri = {};
  final Map<String, List<Track>> _tracksByTitle = {};
  final Map<String, List<Track>> _tracksByFileName = {};
  final Map<String, List<Track>> _tracksByMatchToken = {};
  final Map<String, List<Track>> _knownTracksByMatchToken = {};
  final String? trackMatchKey;

  Track? findKnownByUri(String uri) => _knownByUri[uri];

  Track? findKnownByMatchToken(String token) {
    final matches = _knownTracksByMatchToken[token];
    return matches?.length == 1 ? matches!.single : null;
  }

  Track? findByMatchToken(String token) {
    final matches = _tracksByMatchToken[token];
    return matches?.length == 1 ? matches!.single : null;
  }

  String? matchTokenFor(Track track) => createTrackMatchToken(
    contentFingerprint: track.contentFingerprint,
    trackMatchKey: trackMatchKey,
  );

  Track? find(BackendTrack remote) {
    final exact = _availableByUri[remote.uri];
    if (exact != null) return exact;

    final uri = Uri.tryParse(remote.uri);
    if (isOnlineMusicTrackUri(uri)) {
      return _availableById[onlineMusicTrackId(uri!)];
    }

    final tokenMatch = remote.matchToken == null
        ? null
        : findByMatchToken(remote.matchToken!);
    if (tokenMatch != null) return tokenMatch;

    final candidates = <String, Track>{};
    void addCandidates(List<Track>? values) {
      if (values == null) return;
      for (final track in values) {
        candidates[track.id] = track;
      }
    }

    addCandidates(_tracksByTitle[_normalizeSyncValue(remote.title)]);
    addCandidates(_tracksByFileName[_remoteTrackFileName(remote.uri)]);

    Track? best;
    var bestScore = -1;
    var ambiguous = false;
    for (final candidate in candidates.values) {
      final score = _syncMatchScore(remote, candidate);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
        ambiguous = false;
      } else if (score >= 0 && score == bestScore) {
        ambiguous = true;
      }
    }
    return bestScore < 0 || ambiguous ? null : best;
  }
}

int _syncMatchScore(BackendTrack remote, Track local) {
  final remoteTitle = _normalizeSyncValue(remote.title);
  final localTitle = _normalizeSyncValue(local.title);
  final titleMatches =
      remoteTitle.isNotEmpty &&
      localTitle.isNotEmpty &&
      remoteTitle == localTitle;

  final fileName = _remoteTrackFileName(remote.uri);
  final fileNameMatches =
      fileName.isNotEmpty && fileName == _localTrackFileName(local);
  if (!titleMatches && !fileNameMatches) return -1;

  final artistMatches = _meaningfulMetadataMatches(remote.artist, local.artist);
  final albumMatches = _meaningfulMetadataMatches(remote.album, local.album);
  final remoteDuration = remote.durationMs;
  final localDuration = local.durationMs;
  if (remoteDuration != null &&
      localDuration != null &&
      (remoteDuration - localDuration).abs() > 3000) {
    return -1;
  }
  if (!fileNameMatches && !(artistMatches && albumMatches)) return -1;

  return (titleMatches ? 10 : 0) +
      (fileNameMatches ? 8 : 0) +
      (artistMatches ? 4 : 0) +
      (albumMatches ? 2 : 0) +
      (remoteDuration != null && localDuration != null ? 4 : 0);
}

bool _meaningfulMetadataMatches(String first, String second) {
  final normalizedFirst = _normalizeSyncValue(first);
  final normalizedSecond = _normalizeSyncValue(second);
  const unknownValues = {
    '',
    '未知艺术家',
    '未知专辑',
    'unknown artist',
    'unknown album',
  };
  return !unknownValues.contains(normalizedFirst) &&
      !unknownValues.contains(normalizedSecond) &&
      normalizedFirst == normalizedSecond;
}

String _localTrackFileName(Track track) {
  final filePath = track.filePath;
  if (filePath != null && filePath.isNotEmpty) {
    return _pathFileName(filePath);
  }
  final uriFileName = _remoteTrackFileName(track.uri);
  if (_hasFileExtension(uriFileName)) return uriFileName;
  final sourceFileName = _pathFileName(track.sourceId);
  return _hasFileExtension(sourceFileName) ? sourceFileName : uriFileName;
}

String _remoteTrackFileName(String rawUri) {
  final uri = Uri.tryParse(rawUri);
  if (uri == null || uri.pathSegments.isEmpty) return '';
  return _pathFileName(uri.pathSegments.last);
}

String _pathFileName(String value) =>
    _normalizeSyncValue(value.split(RegExp(r'[/\\]')).last);

bool _hasFileExtension(String value) {
  final dot = value.lastIndexOf('.');
  return dot > 0 && dot < value.length - 1;
}

String _normalizeSyncValue(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
