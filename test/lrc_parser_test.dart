import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_music/core/lyrics/lrc_parser.dart';

void main() {
  test('parses and selects synchronized lyric lines', () {
    final lines = parseLrc('[00:01.00]第一行\n[00:03.50]第二行');

    expect(lines, hasLength(2));
    expect(lyricAt(lines, const Duration(seconds: 2))?.text, '第一行');
    expect(lyricAt(lines, const Duration(seconds: 4))?.text, '第二行');
  });
}
