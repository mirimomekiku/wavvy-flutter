// Pure helpers for finding album covers online: what is worth asking about,
// the search query, how to tell the right release apart and when a miss may be
// asked again. Nothing here touches the network or the disk.

/// A cached miss is not asked about again for this long.
const Duration kArtMissTtl = Duration(days: 30);

/// The album and artist the library has for one album.
class AlbumRef {
  /// Stable, file-name safe cache key (see [albumKey]).
  final String key;
  final String album;
  final String artist;

  const AlbumRef({
    required this.key,
    required this.album,
    required this.artist,
  });

  @override
  String toString() => 'AlbumRef($key, $album, $artist)';
}

/// True for tags that carry no information (an untagged file, MediaStore's
/// `<unknown>`).
bool isUnknownTag(String? value) {
  final v = value?.trim().toLowerCase() ?? '';
  return v.isEmpty || v == '<unknown>' || v == 'unknown';
}

/// Various Artists compilations have no single artist to search for.
bool isVariousArtists(String? artist) {
  final v = normalizeName(artist ?? '');
  return v == 'various artists' || v == 'various' || v == 'va';
}

/// Whether an online lookup makes sense: a real album and a real, single
/// artist. A single without an album tag has nothing to look up.
bool isLookupWorthy(String? album, String? artist) =>
    !isUnknownTag(album) && !isUnknownTag(artist) && !isVariousArtists(artist);

/// File-name safe cache key: `id<albumId>` when MediaStore gave the album an
/// id, otherwise `n<hash>` of the normalized artist and album.
String albumKey({int? albumId, String? album, String? artist}) {
  if (albumId != null) return 'id$albumId';
  return 'n${_hash('${normalizeName(artist ?? '')}\u0000${normalizeName(album ?? '')}')}';
}

/// FNV-1a over the UTF-16 code units, twice with different seeds: stable across
/// runs (unlike String.hashCode) and 64 bits wide.
String _hash(String s) {
  var a = 0x811c9dc5;
  var b = 0x01000193 ^ 0x9747b28c;
  for (final unit in s.codeUnits) {
    a = ((a ^ unit) * 0x01000193) & 0xffffffff;
    b = ((b ^ unit) * 0x01000193) & 0xffffffff;
  }
  return a.toRadixString(16).padLeft(8, '0') +
      b.toRadixString(16).padLeft(8, '0');
}

final _bracketed = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]');
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Lower-case words only: brackets such as "(Deluxe Edition)" are dropped,
/// "&" reads as "and", punctuation is a space and a leading "the" is ignored.
String normalizeName(String input) {
  String clean(String s) => s
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(_nonWord, ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  var out = clean(input.replaceAll(_bracketed, ' '));
  // "(What's the Story)" style titles are all brackets: keep their words.
  if (out.isEmpty) out = clean(input);
  if (out.startsWith('the ') && out.length > 4) out = out.substring(4);
  return out;
}

/// 0..1: 1 for the same words, otherwise the share of words in common.
double nameSimilarity(String a, String b) {
  final x = normalizeName(a);
  final y = normalizeName(b);
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;
  final tx = x.split(' ').toSet();
  final ty = y.split(' ').toSet();
  final shared = tx.intersection(ty).length;
  return shared / (tx.length + ty.length - shared);
}

/// Escapes a value for a double-quoted Lucene phrase: only the backslash and
/// the quote are special inside quotes. Control characters become spaces.
String escapeLucenePhrase(String value) => value
    .replaceAll(RegExp(r'[\u0000-\u001f]'), ' ')
    .replaceAll(r'\', r'\\')
    .replaceAll('"', r'\"')
    .trim();

/// The MusicBrainz release search query for an album.
String buildReleaseQuery(String album, String artist) =>
    'release:"${escapeLucenePhrase(album)}" AND '
    'artist:"${escapeLucenePhrase(artist)}"';

/// The search URL (https only; encoding is done by [Uri]).
Uri buildSearchUri(String album, String artist) => Uri.https(
  'musicbrainz.org',
  '/ws/2/release/',
  {'query': buildReleaseQuery(album, artist), 'fmt': 'json', 'limit': '5'},
);

/// One search hit that looks like the wanted album.
class ReleaseCandidate {
  final String id;
  final String? groupId;

  /// 0..100: MusicBrainz's score scaled by how well the names match.
  final double score;

  const ReleaseCandidate({
    required this.id,
    required this.groupId,
    required this.score,
  });
}

/// The least a hit must score (see [ReleaseCandidate.score]) to be used.
const double kMinReleaseScore = 55;

/// Reads the `releases` of a MusicBrainz search response and returns the hits
/// that match [album] and [artist], best first. Anything unexpected in the
/// JSON is skipped, never thrown.
List<ReleaseCandidate> pickReleases(
  Object? json, {
  required String album,
  required String artist,
}) {
  if (json is! Map || json['releases'] is! List) return const [];
  final out = <ReleaseCandidate>[];
  for (final r in json['releases'] as List) {
    if (r is! Map) continue;
    final id = r['id'];
    final title = r['title'];
    if (id is! String || title is! String) continue;

    final titleSim = nameSimilarity(title, album);
    final names = <String>[];
    final credit = r['artist-credit'];
    if (credit is List) {
      for (final c in credit) {
        if (c is! Map) continue;
        final n = c['name'];
        if (n is String) names.add(n);
        final inner = c['artist'];
        if (inner is Map && inner['name'] is String) {
          names.add(inner['name'] as String);
        }
      }
      // Several credited artists read as one string too ("A & B").
      final joined = credit
          .whereType<Map>()
          .map((c) => '${c['name'] ?? ''}${c['joinphrase'] ?? ''}')
          .join();
      if (joined.isNotEmpty) names.add(joined);
    }
    var artistSim = 0.0;
    for (final n in names) {
      final s = nameSimilarity(n, artist);
      if (s > artistSim) artistSim = s;
    }
    if (titleSim < 0.6 || artistSim < 0.6) continue;

    final mb = r['score'];
    final mbScore = mb is num ? mb.toDouble().clamp(0, 100) : 75.0;
    final group = r['release-group'];
    out.add(
      ReleaseCandidate(
        id: id,
        groupId: group is Map && group['id'] is String
            ? group['id'] as String
            : null,
        score: mbScore * (0.6 * titleSim + 0.4 * artistSim),
      ),
    );
  }
  out.removeWhere((c) => c.score < kMinReleaseScore);
  // Stable: equal scores keep MusicBrainz's own order.
  final indexed = {for (var i = 0; i < out.length; i++) out[i]: i};
  out.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : indexed[a]!.compareTo(indexed[b]!);
  });
  return out;
}

/// Whether a miss recorded at [lastAttempt] still counts at [now].
bool isMissFresh(DateTime lastAttempt, DateTime now) =>
    now.difference(lastAttempt) < kArtMissTtl;
