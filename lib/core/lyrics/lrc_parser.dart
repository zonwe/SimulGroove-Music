class LyricLine {
  const LyricLine(this.time, this.text);

  final Duration time;
  final String text;
}

List<LyricLine> parseLrc(String? source) {
  if (source == null || source.trim().isEmpty) return const [];
  final timestamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final lines = <LyricLine>[];
  for (final rawLine in source.split(RegExp(r'\r?\n'))) {
    final matches = timestamp.allMatches(rawLine).toList(growable: false);
    if (matches.isEmpty) continue;

    final leadingMatches = <RegExpMatch>[];
    var contentStart = 0;
    for (final match in matches) {
      if (rawLine.substring(contentStart, match.start).trim().isNotEmpty) {
        break;
      }
      leadingMatches.add(match);
      contentStart = match.end;
    }
    if (leadingMatches.isEmpty) continue;

    final text = rawLine
        .substring(contentStart)
        .replaceAll(timestamp, '')
        .trim();

    for (final match in leadingMatches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fraction = match.group(3) ?? '0';
      final milliseconds = fraction.length == 3
          ? int.parse(fraction)
          : fraction.length == 2
          ? int.parse(fraction) * 10
          : int.parse(fraction) * 100;
      lines.add(
        LyricLine(
          Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text,
        ),
      );
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

LyricLine? lyricAt(List<LyricLine> lines, Duration position) {
  LyricLine? current;
  for (final line in lines) {
    if (line.time > position) break;
    current = line;
  }
  return current;
}
