import 'dart:convert';

import 'package:flutter_music/core/auth/track_match_token.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PBKDF2-HMAC-SHA256 派生结果符合已知向量', () async {
    final key = await deriveTrackMatchKey(
      password: 'password',
      salt: base64Url.encode(utf8.encode('salt')).replaceAll('=', ''),
      iterations: 1,
    );

    final bytes = base64Url.decode(base64Url.normalize(key));
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(
      hex,
      '120fb6cffcf8b32c43e7225256c4f837'
      'a86548c92ccc35480805987cb70be17b',
    );
  });

  test('曲目匹配令牌稳定且不会暴露原始指纹', () {
    const fingerprint =
        'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

    final first = createTrackMatchToken(
      contentFingerprint: fingerprint,
      trackMatchKey: key,
    );
    final second = createTrackMatchToken(
      contentFingerprint: fingerprint,
      trackMatchKey: key,
    );

    expect(first, second);
    expect(isTrackMatchToken(first), isTrue);
    expect(first, isNot(contains(fingerprint.substring('sha256:'.length))));
    expect(
      createTrackMatchToken(
        contentFingerprint: fingerprint,
        trackMatchKey: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
      ),
      isNot(first),
    );
  });

  test('格式错误的指纹或密钥不会生成令牌', () {
    expect(
      createTrackMatchToken(
        contentFingerprint: 'sha256:not-a-digest',
        trackMatchKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ),
      isNull,
    );
    expect(
      createTrackMatchToken(
        contentFingerprint:
            'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        trackMatchKey: 'invalid',
      ),
      isNull,
    );
    expect(isTrackMatchToken('hmac-sha256:ABC'), isFalse);
  });
}
