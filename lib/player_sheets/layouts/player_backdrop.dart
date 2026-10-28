import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// The song's cover, blurred, as the background of a page: washed with the page
/// color so text on top stays readable in light and dark, tinted with the album
/// color when Album colors is on, and cross-faded when the song changes (at
/// once with reduced motion). A song without a cover (a file opened from
/// outside the library) gets a plain gradient of the theme colors.
///
/// The blur is computed once per cover: the sharp art is small and static
/// under a fixed blur, in its own repaint layer.
class PlayerBackdrop extends ConsumerWidget {
  const PlayerBackdrop({super.key, required this.song});
  final SongModel song;

  /// How much of the page color covers the blurred art.
  static double washAlpha(bool dark) => dark ? 0.8 : 0.86;

  /// How strongly the album color tints it.
  static const double tintAlpha = 0.16;

  /// How long the cross-fade to the next song's cover lasts.
  static const Duration fade = Duration(milliseconds: 350);

  /// The color under text on the backdrop, worst case: [cover] is the average
  /// color of the blurred art, and [scrim] the opacity of any gradient the page
  /// puts on top. Used to check contrast in tests.
  static Color effective({
    required Color cover,
    required Color page,
    required bool dark,
    Color? tint,
    double scrim = 0,
  }) {
    var c = Color.alphaBlend(page.withValues(alpha: washAlpha(dark)), cover);
    if (tint != null) {
      c = Color.alphaBlend(tint.withValues(alpha: tintAlpha), c);
    }
    return Color.alphaBlend(page.withValues(alpha: scrim), c);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final tint = ref.watch(paletteProvider.select((p) => p.playerColor));
    final still = MediaQuery.disableAnimationsOf(context);
    // A textured look has a transparent page color; the wash needs a solid one.
    final page = a.background;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: still ? Duration.zero : fade,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [...previous, ?current],
              ),
              child: KeyedSubtree(
                key: ValueKey(song.id),
                child: song.id < 0
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [a.surfaceHigh, a.surface],
                          ),
                        ),
                      )
                    : RepaintBoundary(
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                            sigmaX: 28,
                            sigmaY: 28,
                            tileMode: TileMode.clamp,
                          ),
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox.square(
                              dimension: 160,
                              child: wvArtwork(
                                context,
                                id: song.id,
                                type: ArtworkType.AUDIO,
                                size: 160,
                                placeholder: Icons.music_note_rounded,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            ColoredBox(color: page.withValues(alpha: washAlpha(a.dark))),
            AnimatedContainer(
              duration: still ? Duration.zero : fade,
              decoration: BoxDecoration(
                color: tint?.withValues(alpha: tintAlpha) ?? Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
