import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_music/core/lyrics/lrc_parser.dart';

void main() {
  test('parses and selects synchronized lyric lines', () {
    final lines = parseLrc('[00:01.00]第一行\n[00:03.50]第二行');

    expect(lines, hasLength(2));
    expect(lyricAt(lines, const Duration(seconds: 2))?.text, '第一行');
    expect(lyricAt(lines, const Duration(seconds: 4))?.text, '第二行');
  });

  test('ignores a trailing end timestamp instead of duplicating the line', () {
    final lines = parseLrc(
      '[00:05.73] 混音 Mixing Engineer：张步若@RSS Studio[00:06.45]\n'
      '[00:06.45] 乐团 Orchestra：辉音国际爱乐乐团[00:07.17]',
    );

    expect(lines, hasLength(2));
    expect(lines[0].time, const Duration(seconds: 5, milliseconds: 730));
    expect(lines[0].text, '混音 Mixing Engineer：张步若@RSS Studio');
    expect(lines[1].time, const Duration(seconds: 6, milliseconds: 450));
    expect(lines[1].text, '乐团 Orchestra：辉音国际爱乐乐团');
    expect(
      lyricAt(lines, const Duration(seconds: 7))?.text,
      '乐团 Orchestra：辉音国际爱乐乐团',
    );
  });

  test('keeps standard multiple leading timestamps', () {
    final lines = parseLrc('[00:10.00][00:20.00]重复副歌');

    expect(lines, hasLength(2));
    expect(lines.map((line) => line.time), [
      const Duration(seconds: 10),
      const Duration(seconds: 20),
    ]);
    expect(lines.every((line) => line.text == '重复副歌'), isTrue);
  });

  test('removes per-word karaoke timestamps from displayed text', () {
    final lines = parseLrc(
      '[00:04.63]乐[00:04.63][00:04.70]团[00:04.78] '
      '[00:04.78]Orchestra：[00:04.85]辉[00:04.93]音[00:05.00]国'
      '[00:05.08]际[00:05.15]爱[00:05.23]乐[00:05.30]乐[00:05.38]团'
      '[00:05.45]',
    );

    expect(lines, hasLength(1));
    expect(lines.single.time, const Duration(seconds: 4, milliseconds: 630));
    expect(lines.single.text, '乐团 Orchestra：辉音国际爱乐乐团');
    expect(lines.single.text, isNot(contains('[00:')));
  });
}
