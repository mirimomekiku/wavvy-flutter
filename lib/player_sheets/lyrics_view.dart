import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/status_message.dart';

/// The synced lyrics of the playing song as a view to place inside another
/// layout (the Lyrics-first and Two-pane players).
///
/// It has its own scroll controller and follows the current line itself, so it
/// never competes with the sheet's Lyrics page, which uses the shared
/// `lyricsScrollControllerProvider`. Tapping a line seeks there. Lyrics without
/// timestamps show as a block of text, and loading, empty and error states
/// look right at any size.
class LyricsView extends ConsumerStatefulWidget {
  const LyricsView({
    super.key,
    this.activeSize = 26,
    this.inactiveSize = 19,
    this.anchor = 0.4,
    this.textAlign = TextAlign.center,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.fadeEdges = true,
    this.emptyAction,
  });

  /// Font sizes of the current line and of the others.
  final double activeSize;
  final double inactiveSize;

  /// Where the current line sits, as a fraction of the height from the top.
  final double anchor;
  final TextAlign textAlign;

  /// Side padding (top and bottom are added to let every line reach the anchor).
  final EdgeInsets padding;

  /// Fade the lines out at the top and bottom edges.
  final bool fadeEdges;

  /// An extra button under "Try again" when there are no lyrics to show.
  final Widget? emptyAction;

  @override
  ConsumerState<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<LyricsView> {
  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();

  /// Brings [index] to the anchor: smoothly, or at once with reduced motion.
  void _follow(int index) {
    final count = ref.read(lyricsProvider).lyrics.length;
    if (index < 0 || index >= count || !_scroll.isAttached) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(index: index, alignment: widget.anchor);
    } else {
      _scroll.scrollTo(
        index: index,
        alignment: widget.anchor,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsProvider);
    ref.listen(lyricsProvider.select((s) => s.currentIndex), (_, index) {
      _follow(index);
    });

    final lyrics = lyricsState.lyrics;
    if (lyricsState.isLoading) {
      return const Center(child: AquaSpinner(size: 28));
    }
    if (lyrics.isEmpty) {
      final song = ref.watch(playerProvider.select((s) => s.currentSong));
      return WvStatusMessage(
        icon: Icons.lyrics_outlined,
        title: lyricsState.error.isEmpty
            ? 'No lyrics available'
            : 'Lyrics unavailable',
        message: lyricsState.error.isEmpty
            ? 'Lyrics will appear here when they are available.'
            : lyricsState.error,
        action: song == null
            ? widget.emptyAction
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => ref
                        .read(lyricsProvider.notifier)
                        .fetchLyrics(
                          trackName: song.title,
                          artistName: song.artist ?? '',
                          albumName: song.album ?? '',
                          duration: (song.duration ?? 0) ~/ 1000,
                        ),
                    child: const Text('Try again'),
                  ),
                  ?widget.emptyAction,
                ],
              ),
      );
    }
    // Lyrics without timestamps arrive as one block at time zero.
    if (lyrics.length == 1 && lyrics.first.time == Duration.zero) {
      return _PlainText(
        text: lyrics.first.text,
        size: widget.activeSize,
        align: widget.textAlign,
        padding: widget.padding,
      );
    }
    return _SyncedLines(
      lyrics: lyrics,
      current: lyricsState.currentIndex,
      view: widget,
      controller: _scroll,
      positions: _positions,
      onSeek: (time) => ref.read(playerProvider.notifier).seek(time),
    );
  }
}

class _SyncedLines extends StatelessWidget {
  const _SyncedLines({
    required this.lyrics,
    required this.current,
    required this.view,
    required this.controller,
    required this.positions,
    required this.onSeek,
  });
  final List<Lyric> lyrics;
  final int current;
  final LyricsView view;
  final ItemScrollController controller;
  final ItemPositionsListener positions;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        // Room above and below so the first and last lines can reach the
        // anchor too.
        final height = c.maxHeight.isFinite ? c.maxHeight : 300.0;
        final list = ScrollablePositionedList.builder(
          itemCount: lyrics.length,
          physics: const BouncingScrollPhysics(),
          itemScrollController: controller,
          itemPositionsListener: positions,
          initialScrollIndex: math.max(0, math.min(current, lyrics.length - 1)),
          initialAlignment: view.anchor,
          padding: view.padding.copyWith(
            top: height * view.anchor,
            bottom: height * (1 - view.anchor),
          ),
          itemBuilder: (context, index) {
            final isActive = index == current;
            final isPast = current >= 0 && index < current;
            final color = isActive
                ? a.text
                : a.textSecondary.withValues(alpha: isPast ? 0.4 : 0.7);
            return Semantics(
              button: true,
              label: lyrics[index].text,
              excludeSemantics: true,
              selected: isActive,
              onTap: () => onSeek(lyrics[index].time),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSeek(lyrics[index].time),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    textAlign: view.textAlign,
                    style: TextStyle(
                      color: color,
                      fontSize: isActive ? view.activeSize : view.inactiveSize,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      height: 1.25,
                      letterSpacing: -0.3,
                    ),
                    child: Text(lyrics[index].text, textAlign: view.textAlign),
                  ),
                ),
              ),
            );
          },
        );
        if (!view.fadeEdges) return list;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0, 0.08, 0.9, 1],
          ).createShader(rect),
          child: list,
        );
      },
    );
  }
}

/// Lyrics without timestamps: plain text to read, nothing to follow or tap.
class _PlainText extends StatelessWidget {
  const _PlainText({
    required this.text,
    required this.size,
    required this.align,
    required this.padding,
  });
  final String text;
  final double size;
  final TextAlign align;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: padding.copyWith(top: 12, bottom: 32),
      children: [
        Text(
          'Lyrics are not synced to the music',
          textAlign: align,
          style: TextStyle(fontSize: 12, color: a.textSecondary),
        ),
        const SizedBox(height: 16),
        Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontSize: size * 0.85,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: a.text,
          ),
        ),
      ],
    );
  }
}
