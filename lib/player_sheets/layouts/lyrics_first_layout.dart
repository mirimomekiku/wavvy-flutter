import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout_data.dart';
import 'package:wavvy/player_sheets/lyrics_fullscreen.dart';
import 'package:wavvy/player_sheets/lyrics_view.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/audio_effects/effects.screen.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/status_message.dart';

/// The least height the lyrics get before the whole page scrolls instead.
const double kLyricsFirstMinLyrics = 150;

/// For singing along: a small cover with the title on top, the lyrics taking
/// most of the screen and compact controls at the bottom. Without lyrics (or
/// with them turned off) the lyrics area can show a large cover instead.
class LyricsFirstLayout extends ConsumerStatefulWidget {
  const LyricsFirstLayout({super.key, required this.data});
  final PlayerLayoutData data;

  @override
  ConsumerState<LyricsFirstLayout> createState() => _LyricsFirstLayoutState();
}

class _LyricsFirstLayoutState extends ConsumerState<LyricsFirstLayout> {
  /// Whether the large cover replaces the lyrics. Kept for the song that
  /// plays and cleared when the song changes.
  bool _cover = false;

  @override
  void didUpdateWidget(LyricsFirstLayout old) {
    super.didUpdateWidget(old);
    if (old.data.song.id != widget.data.song.id) _cover = false;
  }

  void _setCover(bool value) => setState(() => _cover = value);

  @override
  Widget build(BuildContext context) {
    final song = widget.data.song;
    final scaler = MediaQuery.textScalerOf(context);
    final enabled = ref.watch(
      settingsProvider.select((s) => s.enableLyricsFetching),
    );
    return LayoutBuilder(
      builder: (context, c) {
        // What the header and the controls need, with room to spare for the
        // text scale. The lyrics get the rest.
        final header =
            math.max(
              56.0,
              scaler.scale(16) * 1.15 + 4 + scaler.scale(12) * 1.25,
            ) +
            14;
        final seek = 34 + scaler.scale(11.5) * 1.4 + 16;
        const transport = 44.0;
        const modes = 36.0;
        final controls = seek + 8 + transport + 8 + modes + 12;
        const extras = 34.0 + 6;
        final showExtras =
            c.hasBoundedHeight &&
            c.maxHeight >= header + controls + extras + 230;
        final fixed = header + controls + (showExtras ? extras : 0);
        final fits =
            c.hasBoundedHeight && c.maxHeight - fixed >= kLyricsFirstMinLyrics;

        final headerRow = _Header(
          data: widget.data,
          onFullscreen: widget.data.onLyrics == null
              ? null
              : () => LyricsFullscreenPage.open(context),
        );
        final lyrics = _LyricsArea(
          song: song,
          enabled: enabled,
          cover: _cover,
          onCover: _setCover,
        );
        final controlsColumn = _Controls(song: song, showExtras: showExtras);

        final Widget body = fits
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  headerRow,
                  Expanded(child: lyrics),
                  controlsColumn,
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    headerRow,
                    SizedBox(height: kLyricsFirstMinLyrics, child: lyrics),
                    controlsColumn,
                  ],
                ),
              );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: body,
          ),
        );
      },
    );
  }
}

/// The small cover, title and artist, the heart and the full-screen button.
class _Header extends StatelessWidget {
  const _Header({required this.data, required this.onFullscreen});
  final PlayerLayoutData data;
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) {
    final song = data.song;
    final still = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: still ? Duration.zero : const Duration(milliseconds: 300),
            child: PlayerCover(
              key: ValueKey(song.id),
              song: song,
              size: 56,
              radius: 10,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PlayerTitleBlock(
              song: song,
              onArtist: data.onArtist,
              titleSize: 16,
              artistSize: 12,
              titleLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          PlayerFavoriteButton(song: song, size: 40),
          if (onFullscreen != null) ...[
            const SizedBox(width: 6),
            WvButton(
              circular: true,
              squircle: true,
              size: 40,
              tooltip: 'Full-screen lyrics',
              onPressed: onFullscreen,
              child: const Icon(Icons.fullscreen_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

/// The lyrics, or the large cover when that is chosen.
class _LyricsArea extends StatelessWidget {
  const _LyricsArea({
    required this.song,
    required this.enabled,
    required this.cover,
    required this.onCover,
  });
  final SongModel song;
  final bool enabled;
  final bool cover;
  final ValueChanged<bool> onCover;

  @override
  Widget build(BuildContext context) {
    if (cover) {
      return _BigCover(song: song, onLyrics: () => onCover(false));
    }
    final showCover = TextButton(
      onPressed: () => onCover(true),
      child: const Text('Show the cover'),
    );
    if (!enabled) {
      return WvStatusMessage(
        icon: Icons.lyrics_outlined,
        title: 'Lyrics are turned off',
        message: 'Turn on lyrics in Settings to see them here.',
        action: showCover,
      );
    }
    return LyricsView(
      activeSize: 28,
      inactiveSize: 21,
      anchor: 0.38,
      emptyAction: showCover,
    );
  }
}

/// A large cover in place of the lyrics, with a way back.
class _BigCover extends StatelessWidget {
  const _BigCover({required this.song, required this.onLyrics});
  final SongModel song;
  final VoidCallback onLyrics;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.max(
          40.0,
          math.min(c.maxWidth - 48, c.maxHeight - 56),
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: AnimatedSwitcher(
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                child: PlayerCover(
                  key: ValueKey(song.id),
                  song: song,
                  size: side,
                  radius: 18,
                ),
              ),
            ),
            TextButton(onPressed: onLyrics, child: const Text('Show lyrics')),
          ],
        );
      },
    );
  }
}

/// The seek row, a small transport, shuffle, repeat and Sound, and (when there
/// is room) the extras row.
class _Controls extends ConsumerWidget {
  const _Controls({required this.song, required this.showExtras});
  final SongModel song;
  final bool showExtras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shuffle = ref.watch(
      playerProvider.select((s) => s.isShuffleModeEnabled),
    );
    final loop = ref.watch(playerProvider.select((s) => s.loopMode));
    final controls = ref.read(playerProvider.notifier);
    Widget mode(
      String tooltip,
      IconData icon,
      bool selected,
      VoidCallback onPressed,
    ) => Expanded(
      child: Semantics(
        selected: selected,
        child: WvButton(
          size: 36,
          primary: selected,
          tooltip: tooltip,
          onPressed: onPressed,
          child: Icon(icon, size: 20),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerSeekRow(song: song),
          const SizedBox(height: 8),
          const PlayerTransport(
            sideHeight: 40,
            playHeight: 44,
            playWidth: 72,
            sideIcon: 24,
            playIcon: 28,
            gap: 10,
          ),
          if (showExtras) ...[const SizedBox(height: 6), const PlayerExtras()],
          const SizedBox(height: 8),
          Row(
            children: [
              mode(
                shuffle ? 'Shuffle on' : 'Shuffle',
                Icons.shuffle_rounded,
                shuffle,
                controls.toggleShuffle,
              ),
              const SizedBox(width: 10),
              mode(
                loop.name == 'off' ? 'Repeat' : 'Repeat ${loop.name}',
                PlayerUtils.getLoopIcon(loop),
                loop.name != 'off',
                controls.cycleLoopMode,
              ),
              const SizedBox(width: 10),
              mode(
                'Sound',
                Icons.tune_rounded,
                false,
                () => AppNav.push(const AudioEffectsScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The picker thumbnail: a small cover and two text bars, then centered lines
/// with one in the accent color.
class LyricsFirstLayoutPreview extends StatelessWidget {
  const LyricsFirstLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return CustomPaint(
      painter: _PreviewPainter(
        text: a.textSecondary,
        accent: a.accent,
        cover: a.outline,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({
    required this.text,
    required this.accent,
    required this.cover,
  });
  final Color text;
  final Color accent;
  final Color cover;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint();
    void bar(double cx, double y, double width, double height, Color color) {
      fill.color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, y + height / 2),
            width: width,
            height: height,
          ),
          Radius.circular(height / 2),
        ),
        fill,
      );
    }

    final pad = w * 0.1;
    final square = w * 0.2;
    fill.color = cover.withValues(alpha: 0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, square, square),
        Radius.circular(square * 0.2),
      ),
      fill,
    );
    final left = pad + square + w * 0.06;
    final barH = h * 0.035;
    bar(left + w * 0.2, pad + square * 0.22, w * 0.4, barH, text);
    bar(
      left + w * 0.14,
      pad + square * 0.6,
      w * 0.28,
      barH * 0.8,
      text.withValues(alpha: 0.5),
    );
    final widths = [0.55, 0.7, 0.62, 0.7, 0.5];
    var y = pad + square + h * 0.1;
    for (var i = 0; i < widths.length; i++) {
      final active = i == 2;
      bar(
        w / 2,
        y,
        w * widths[i],
        active ? barH * 1.5 : barH,
        active ? accent : text.withValues(alpha: i < 2 ? 0.35 : 0.55),
      );
      y += h * (active ? 0.1 : 0.085);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.text != text || old.accent != accent || old.cover != cover;
}
