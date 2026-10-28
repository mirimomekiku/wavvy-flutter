import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/audio_quality.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// A small Aqua capsule that says what a file is: silver for lossy, blue gel
/// for Lossless, gold-tinted gel for Hi-Res. [compact] uses the short text
/// ("FLAC 24/96"). The text scales down rather than overflowing, and the
/// capsule is one Semantics node ("Lossless, FLAC, 24-bit, 96 kilohertz").
class AquaQualityBadge extends StatelessWidget {
  const AquaQualityBadge({
    super.key,
    required this.quality,
    this.compact = false,
  });
  final AudioQuality quality;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!quality.hasData) return const SizedBox.shrink();
    final a = Wv.of(context);
    final tier = quality.tier;
    final text = compact ? quality.shortLabel : quality.label;
    if (text.isEmpty) return const SizedBox.shrink();

    final Gradient gradient;
    final Color border;
    final Color color;
    switch (tier) {
      case QualityTier.lossy:
        gradient = a.gelGradient();
        border = a.dark ? const Color(0xFF1B2026) : const Color(0xFF9AA0A6);
        color = a.textSecondary;
      case QualityTier.lossless:
        gradient = _gel(const Color(0xFF2F6BC2));
        border = const Color(0xFF1E4F96);
        color = Colors.white;
      case QualityTier.hiRes:
        gradient = _gel(const Color(0xFFE2B02E));
        border = const Color(0xFF9C7410);
        color = const Color(0xFF3A2A00);
    }

    return Semantics(
      label: quality.semanticsLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: a.dark ? 0.05 : 0.7),
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tier == QualityTier.hiRes) ...[
                Icon(Icons.star_rounded, size: 11, color: color),
                const SizedBox(width: 3),
              ],
              Text(
                text,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Aqua gel in a given color: bright top, a crisp midline, a lit bottom.
  static LinearGradient _gel(Color base) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.lerp(base, Colors.white, 0.30)!,
      Color.lerp(base, Colors.white, 0.06)!,
      base,
      Color.lerp(base, Colors.white, 0.10)!,
    ],
    stops: const [0, 0.45, 0.52, 1],
  );
}

/// The quality badge of a song: the quick estimate at once, the probed details
/// when they arrive. The probe is one native call per song, cached, and runs
/// only for the song a screen asks about, never per list row.
class SongQualityBadge extends ConsumerWidget {
  const SongQualityBadge({super.key, required this.song, this.compact = false});
  final SongModel song;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = QualityKey.fromSong(song);
    final quality = ref.watch(audioQualityProvider(key)).value ?? key.estimate;
    return AquaQualityBadge(quality: quality, compact: compact);
  }
}
