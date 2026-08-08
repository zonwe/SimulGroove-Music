/// Splits the common multi-artist separators used in local music tags.
/// The original tag is kept in the database; this is only for grouping and
/// artist collection lookup.
List<String> splitArtistNames(String value) {
  final normalized = value.replaceAll(
    RegExp(r'\s+(?:feat\.?|ft\.?|featuring)\s+', caseSensitive: false),
    ',',
  );
  return normalized
      .split(RegExp(r'\s*(?:,|&|/|;|、|，|\|)\s*'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

bool artistTagContains(String tag, String artist) {
  final query = artist.trim().toLowerCase();
  if (query.isEmpty) return false;
  return splitArtistNames(tag).any((name) => name.toLowerCase() == query);
}
