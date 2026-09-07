import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

const trackMatchTokenPrefix = 'hmac-sha256:';
const _contentFingerprintPrefix = 'sha256:';
const _derivedKeyLength = 32;
const _defaultPbkdf2Iterations = 210000;

Future<String> deriveTrackMatchKey({
  required String password,
  required String salt,
  int iterations = _defaultPbkdf2Iterations,
}) async {
  if (password.isEmpty) throw const FormatException('密码不能为空。');
  if (iterations <= 0) throw const FormatException('密钥派生轮数无效。');
  final saltBytes = _decodeBase64Url(salt);
  if (saltBytes.isEmpty) throw const FormatException('曲目匹配盐值无效。');
  return compute(_deriveTrackMatchKey, {
    'password': password,
    'salt': salt,
    'iterations': iterations,
  });
}

String? createTrackMatchToken({
  required String? contentFingerprint,
  required String? trackMatchKey,
}) {
  if (!_isContentFingerprint(contentFingerprint) || trackMatchKey == null) {
    return null;
  }
  final key = _tryDecodeBase64Url(trackMatchKey);
  if (key == null || key.length != _derivedKeyLength) return null;
  final digest = Hmac(sha256, key).convert(utf8.encode(contentFingerprint!));
  return '$trackMatchTokenPrefix$digest';
}

bool isTrackMatchToken(String? value) {
  if (value == null ||
      value.length != trackMatchTokenPrefix.length + 64 ||
      !value.startsWith(trackMatchTokenPrefix)) {
    return false;
  }
  final digest = value.substring(trackMatchTokenPrefix.length);
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(digest);
}

String _deriveTrackMatchKey(Map<String, Object> input) {
  final password = input['password']! as String;
  final salt = _decodeBase64Url(input['salt']! as String);
  final iterations = input['iterations']! as int;
  final hmac = Hmac(sha256, utf8.encode(password));
  final block = Uint8List(salt.length + 4)..setAll(0, salt);
  block.setAll(salt.length, const [0, 0, 0, 1]);

  var previous = Uint8List.fromList(hmac.convert(block).bytes);
  final result = Uint8List.fromList(previous);
  for (var iteration = 1; iteration < iterations; iteration++) {
    previous = Uint8List.fromList(hmac.convert(previous).bytes);
    for (var index = 0; index < result.length; index++) {
      result[index] ^= previous[index];
    }
  }
  return base64Url.encode(result).replaceAll('=', '');
}

bool _isContentFingerprint(String? value) {
  if (value == null ||
      value.length != _contentFingerprintPrefix.length + 64 ||
      !value.startsWith(_contentFingerprintPrefix)) {
    return false;
  }
  return RegExp(
    r'^[0-9a-f]{64}$',
  ).hasMatch(value.substring(_contentFingerprintPrefix.length));
}

Uint8List _decodeBase64Url(String value) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));

Uint8List? _tryDecodeBase64Url(String value) {
  try {
    return _decodeBase64Url(value);
  } on FormatException {
    return null;
  }
}
