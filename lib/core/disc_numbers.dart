import 'package:on_audio_query/on_audio_query.dart';

// Android's MediaStore stores a multi-disc track as `disc * 1000 + track`
// (2003 = disc 2, track 3); on_audio_query returns that value unchanged in
// `SongModel.track`. A plain value (7) or none at all means disc 1.

/// The disc a [track] value belongs to; 1 when it has no disc part.
int discOf(int? track) {
  if (track == null || track < 1000) return 1;
  return track ~/ 1000;
}

/// The track number within its disc, or null when the tag is missing (null,
/// zero, negative, or an encoded value with no track part such as 2000).
int? trackNumberOf(int? track) {
  if (track == null || track <= 0) return null;
  final n = track >= 1000 ? track % 1000 : track;
  return n > 0 ? n : null;
}

/// "Disc 2 - Track 3", "Track 3", "Disc 2", or null with no tags at all.
/// The disc is named only for a multi-disc value (2003) or when [forceDisc].
String? trackLabelOf(int? track, {bool forceDisc = false}) {
  final n = trackNumberOf(track);
  final multi = track != null && track >= 1000;
  final parts = [
    if (multi || (forceDisc && n != null)) 'Disc ${discOf(track)}',
    if (n != null) 'Track $n',
  ];
  return parts.isEmpty ? null : parts.join(' - ');
}

/// One disc of an album, its songs in track order.
class DiscGroup {
  const DiscGroup(this.disc, this.songs);
  final int disc;
  final List<SongModel> songs;
}

/// Splits [songs] into discs in order. Within a disc songs go by track number,
/// then title; songs with no track number follow the numbered ones, by title.
/// Equal songs keep their incoming order, so the result is stable.
List<DiscGroup> groupByDisc(Iterable<SongModel> songs) {
  final indexed = [
    for (final (i, s) in songs.indexed)
      (
        index: i,
        song: s,
        disc: discOf(s.track),
        number: trackNumberOf(s.track),
      ),
  ];
  indexed.sort((a, b) {
    var c = a.disc.compareTo(b.disc);
    if (c != 0) return c;
    // Numbered songs first.
    if ((a.number == null) != (b.number == null)) {
      return a.number == null ? 1 : -1;
    }
    if (a.number != null) {
      c = a.number!.compareTo(b.number!);
      if (c != 0) return c;
    }
    c = a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase());
    if (c != 0) return c;
    return a.index.compareTo(b.index);
  });
  final groups = <DiscGroup>[];
  for (final entry in indexed) {
    if (groups.isEmpty || groups.last.disc != entry.disc) {
      groups.add(DiscGroup(entry.disc, []));
    }
    groups.last.songs.add(entry.song);
  }
  return groups;
}

/// [songs] flattened in (disc, track) order.
List<SongModel> sortByDisc(Iterable<SongModel> songs) => [
  for (final group in groupByDisc(songs)) ...group.songs,
];
