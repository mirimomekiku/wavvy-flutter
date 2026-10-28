import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/playback/ab_loop.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout_data.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/aqua_quality_badge.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// The Mac OS X iTunes look: a recessed LCD with the song, its artist and the
/// scrubber, a big bezeled cover with a glass reflection under it, then the
/// gel transport with the heart and lyrics beside it, extras and mode dock.
class ItunesLayout extends StatelessWidget {
  const ItunesLayout({super.key, required this.data});
  final PlayerLayoutData data;

  /// Height of everything except the cover and its reflection at 1.0 text
  /// scale: the LCD, extras, transport, the mode dock and the gaps.
  static const double _chrome = 340;

  /// How much of the cover the reflection shows.
  static const double reflectionFactor = 0.32;

  @override
  Widget build(BuildContext context) {
    final song = data.song;
    final scaler = MediaQuery.textScalerOf(context);
    // Text grows the LCD (title, artist, times) and little else.
    final chrome = _chrome + (scaler.scale(14) - 14) * 5;
    return LayoutBuilder(
      builder: (context, c) {
        final width = math.min(c.maxWidth, 480.0) - 32;
        final fit = (c.maxHeight - chrome) / (1 + reflectionFactor);
        final side = math.min(width, math.max(120.0, fit));
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ItunesLcdPanel(song: song, onArtist: data.onArtist),
                      const SizedBox(height: 12),
                      Center(
                        child: ItunesCover(
                          key: const Key('itunes_cover'),
                          song: song,
                          size: side,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const PlayerExtras(),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          PlayerFavoriteButton(song: song, size: 40),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: PlayerTransport(
                              sideHeight: 48,
                              playHeight: 56,
                              playWidth: 68,
                              sideIcon: 26,
                              playIcon: 30,
                              gap: 6,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (data.onLyrics != null)
                            WvButton(
                              circular: true,
                              squircle: true,
                              size: 40,
                              tooltip: 'View lyrics',
                              onPressed: data.onLyrics,
                              child: const Icon(Icons.lyrics_outlined),
                            )
                          else
                            const SizedBox(width: 40),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const PlayerModeDock(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The recessed display: title, "Artist - Album", the elapsed and remaining
/// time around the scrubber, and the quality badge.
class ItunesLcdPanel extends ConsumerStatefulWidget {
  const ItunesLcdPanel({super.key, required this.song, this.onArtist});
  final SongModel song;
  final VoidCallback? onArtist;

  @override
  ConsumerState<ItunesLcdPanel> createState() => _ItunesLcdPanelState();
}

class _ItunesLcdPanelState extends ConsumerState<ItunesLcdPanel> {
  /// Where the thumb is while it is dragged (milliseconds). The player is
  /// only asked to seek when the finger lifts, as in [PlayerSeekRow].
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final song = widget.song;
    final duration = ref.watch(durationProvider);
    final playing = ref.watch(positionProvider);
    final controls = ref.read(playerProvider.notifier);
    final loop = ref.watch(abLoopProvider);
    final position = _drag == null
        ? playing
        : Duration(milliseconds: _drag!.round());
    final max = math.max(1.0, duration.inMilliseconds.toDouble());
    final remaining = duration > position ? duration - position : Duration.zero;
    final time = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: a.text,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final artist = song.artist ?? 'Unknown Artist';
    final album = song.album;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: a.lcdDecoration.copyWith(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            song.title,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: a.text,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onArtist,
            child: Text(
              album == null || album.isEmpty ? artist : '$artist - $album',
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: a.textSecondary),
            ),
          ),
          const SizedBox(height: 2),
          AquaSeekBar(
            value: position.inMilliseconds.toDouble().clamp(0.0, max),
            max: max,
            step: 5000,
            loopStart: loop.start?.inMilliseconds.toDouble(),
            loopEnd: loop.end?.inMilliseconds.toDouble(),
            onChanged: (v) {
              if (duration > Duration.zero) setState(() => _drag = v);
            },
            onChangeEnd: (v) {
              if (duration <= Duration.zero) {
                setState(() => _drag = null);
                return;
              }
              // Keep the thumb where it was dropped until the player moved.
              controls.seek(Duration(milliseconds: v.toInt())).whenComplete(() {
                if (mounted) setState(() => _drag = null);
              });
            },
          ),
          Row(
            children: [
              Text(PlayerUtils.formatDuration(position), style: time),
              Expanded(
                child: Center(
                  child: SongQualityBadge(song: song, compact: true),
                ),
              ),
              Text('-${PlayerUtils.formatDuration(remaining)}', style: time),
            ],
          ),
        ],
      ),
    );
  }
}

/// A big square cover in a thin chrome bezel with a glass reflection under it.
/// The reflection is a flipped, faded copy of the cover, painted once inside
/// its own repaint boundary.
class ItunesCover extends StatelessWidget {
  const ItunesCover({super.key, required this.song, required this.size});
  final SongModel song;
  final double size;

  static const double _bezel = 4;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final inner = size - _bezel * 2;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final art = SizedBox.square(
      dimension: inner,
      child: wvArtwork(
        context,
        id: song.id,
        type: ArtworkType.AUDIO,
        size: inner,
        placeholder: Icons.music_note_rounded,
      ),
    );
    final cover = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(_bezel),
          decoration: BoxDecoration(
            gradient: a.chromeGradient,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: a.outline.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: a.scheme.shadow.withValues(alpha: a.dark ? 0.35 : 0.2),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(1), child: art),
        ),
        // Semantics of the copy would only read the cover twice.
        ExcludeSemantics(
          child: RepaintBoundary(
            child: SizedBox(
              width: size,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: ItunesLayout.reflectionFactor,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: a.dark ? 0.38 : 0.5),
                        Colors.transparent,
                      ],
                      stops: [0, ItunesLayout.reflectionFactor],
                    ).createShader(r),
                    child: Transform.flip(
                      flipY: true,
                      child: Padding(
                        padding: const EdgeInsets.all(_bezel),
                        child: art,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return Semantics(
      label: 'Cover of ${song.title}',
      image: true,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(song.id), child: cover),
      ),
    );
  }
}

/// The picker thumbnail: a small LCD bar over a square with a reflection.
class ItunesLayoutPreview extends StatelessWidget {
  const ItunesLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Container(
            height: 16,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: a.lcdDecoration.copyWith(
              borderRadius: BorderRadius.circular(4),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.55,
                child: Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: a.textSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1 / (1 + ItunesLayout.reflectionFactor),
                child: Column(
                  children: [
                    Expanded(
                      flex: 100,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              a.accent,
                              Color.lerp(a.accent, a.text, 0.45)!,
                            ],
                          ),
                          border: Border.all(color: a.outline),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    Expanded(
                      flex: (ItunesLayout.reflectionFactor * 100).round(),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              a.accent.withValues(alpha: 0.4),
                              a.accent.withValues(alpha: 0),
                            ],
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: i == 1 ? 14 : 10,
                  height: i == 1 ? 14 : 10,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: a.gelGradient(primary: i == 1),
                    border: Border.all(color: a.outline, width: 0.5),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
