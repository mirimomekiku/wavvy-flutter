import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/audio_quality.dart';
import 'package:wavvy/core/disc_numbers.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/aqua_quality_badge.dart';

/// The rows of the Song Details table: the file's tags plus its disc and track
/// and, once known, its audio quality. [quality] is the estimate while the
/// native probe runs, so Sample rate and Bit depth show only when they are
/// known ([probed]) and then say "Unknown" if the file does not tell.
List<(String, String)> songInfoRows(
  SongModel song,
  AudioQuality? quality, {
  bool probed = true,
}) {
  final rows = <(String, String)>[];
  for (final row in PlayerUtils.songDetails(song)) {
    rows.add(row);
    if (row.$1 == 'Album') {
      int? track;
      try {
        track = song.track;
      } catch (_) {}
      final label = trackLabelOf(track);
      if (label != null) rows.add(('Track', label));
    }
    if (row.$1 == 'Format' && quality != null && quality.hasData) {
      rows.addAll([
        ('Quality', quality.tierName),
        if (quality.codec != null) ('Codec', quality.codec!),
        if (probed || quality.sampleRate != null)
          (
            'Sample rate',
            quality.sampleRate == null
                ? 'Unknown'
                : '${formatKhz(quality.sampleRate!)} kHz',
          ),
        if (probed || quality.bitDepth != null)
          (
            'Bit depth',
            quality.bitDepth == null ? 'Unknown' : '${quality.bitDepth}-bit',
          ),
        if (quality.bitrate != null)
          (
            quality.estimated ? 'Bitrate (avg)' : 'Bitrate',
            '${(quality.bitrate! / 1000).round()} kbps',
          ),
        if (quality.channels != null)
          ('Channels', channelsLabel(quality.channels!)),
      ]);
    }
  }
  return rows;
}

/// The Song Details content: the quality badge over a striped key / value
/// table. Watches the song's quality, so it fills in when the probe returns.
class SongInfoTable extends ConsumerWidget {
  const SongInfoTable({super.key, required this.song});
  final SongModel song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final key = QualityKey.fromSong(song);
    final async = ref.watch(audioQualityProvider(key));
    final probed = async.hasValue;
    final quality = async.value ?? key.estimate;
    final rows = songInfoRows(song, quality, probed: probed);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quality.hasData)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AquaQualityBadge(quality: quality),
            ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: a.outline.withValues(alpha: 0.55)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    ColoredBox(
                      color: i.isOdd ? a.stripe : a.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 84,
                              child: Text(
                                rows[i].$1,
                                style: TextStyle(
                                  color: a.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                rows[i].$2,
                                style: TextStyle(
                                  color: a.text,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
