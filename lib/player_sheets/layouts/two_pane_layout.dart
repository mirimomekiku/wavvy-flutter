import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/player_sheets/layouts/layout_parts.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/player_sheets/lyrics_fullscreen.dart';
import 'package:wavvy/player_sheets/lyrics_view.dart';
import 'package:wavvy/player_sheets/queue_page.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/lyric_card.dart';
import 'package:wavvy/widgets/seekable_artwork.dart';

/// What the right pane (or, stacked, the lower part) of the two-pane layout shows.
enum TwoPaneTab { queue, lyrics }

/// The pane the user chose. It lives outside the layout so it is kept while the
/// sheet visits another page (the layout is rebuilt on return), and it is only
/// this one value: nothing else of the layout is kept.
final twoPaneTabProvider = NotifierProvider<TwoPaneTabNotifier, TwoPaneTab>(
  TwoPaneTabNotifier.new,
);

class TwoPaneTabNotifier extends Notifier<TwoPaneTab> {
  @override
  TwoPaneTab build() => TwoPaneTab.queue;

  void set(TwoPaneTab tab) => state = tab;
}

/// The player on one side and the queue or the lyrics on the other, for
/// landscape phones and tablets. On a narrow screen (the layout picked by hand)
/// the same pieces are stacked: compact controls on top, the tabs below.
class TwoPaneLayout extends ConsumerWidget {
  const TwoPaneLayout({super.key, required this.data});
  final PlayerLayoutData data;

  /// Below this height of the left pane the cover shrinks to a thumbnail
  /// beside the title, so the controls keep their room.
  static const _shortPane = 440.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = isWidePlayerScreen(MediaQuery.sizeOf(context));
    final lyricsOn = data.onLyrics != null;
    final tab = lyricsOn ? ref.watch(twoPaneTabProvider) : TwoPaneTab.queue;
    void showLyrics() =>
        ref.read(twoPaneTabProvider.notifier).set(TwoPaneTab.lyrics);
    final panes = _Panes(
      tab: tab,
      lyricsOn: lyricsOn,
      onTab: ref.read(twoPaneTabProvider.notifier).set,
    );
    final a = Wv.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        if (!wide) {
          return _stacked(c, panes, lyricsOn ? showLyrics : null);
        }
        // About 45/55 on a landscape phone, 40/60 on a tablet, never less than
        // the controls need.
        final ratio = c.maxHeight >= 600 ? 0.4 : 0.45;
        final left = (c.maxWidth * ratio)
            .clamp(math.min(340.0, c.maxWidth * 0.6), c.maxWidth * 0.6)
            .toDouble();
        return Row(
          children: [
            SizedBox(
              width: left,
              child: _PlayerPane(
                data: data,
                onLyrics: lyricsOn ? showLyrics : null,
                height: c.maxHeight,
                width: left,
              ),
            ),
            Container(
              width: 1,
              decoration: BoxDecoration(
                color: a.separator,
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: a.dark ? 0.04 : 0.6),
                    offset: const Offset(1, 0),
                  ),
                ],
              ),
            ),
            Expanded(child: panes),
          ],
        );
      },
    );
  }

  Widget _stacked(BoxConstraints c, Widget panes, VoidCallback? onLyrics) {
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: c.maxHeight * 0.4),
          child: _PlayerPane(
            data: data,
            onLyrics: onLyrics,
            height: 0,
            width: c.maxWidth,
            stacked: true,
          ),
        ),
        Expanded(child: panes),
      ],
    );
  }
}

/// The cover, title, seek bar and controls.
class _PlayerPane extends StatelessWidget {
  const _PlayerPane({
    required this.data,
    required this.onLyrics,
    required this.height,
    required this.width,
    this.stacked = false,
  });
  final PlayerLayoutData data;
  final VoidCallback? onLyrics;
  final double height;
  final double width;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final song = data.song;
    final compact = stacked || height < TwoPaneLayout._shortPane;
    final inner = math.max(0.0, width - 32);
    final side = compact
        ? 0.0
        : (height - 340).clamp(120.0, math.min(inner, 360.0)).toDouble();
    const transport = PlayerTransport(
      sideHeight: 46,
      playHeight: 52,
      playWidth: 76,
      sideIcon: 26,
      playIcon: 30,
      gap: 10,
    );
    final content = Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 8 : 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact)
            Row(
              children: [
                PlayerCover(song: song, size: 64, radius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: PlayerTitleBlock(
                    song: song,
                    onArtist: data.onArtist,
                    titleSize: 17,
                    artistSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                PlayerSongActions(song: song, onLyrics: onLyrics, size: 38),
              ],
            )
          else ...[
            Center(
              child: SizedBox.square(
                dimension: side,
                child: AnimatedSeekableArtwork(
                  song: song,
                  size: side,
                  iconColor: a.text,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: PlayerTitleBlock(
                    song: song,
                    onArtist: data.onArtist,
                    titleSize: 20,
                  ),
                ),
                const SizedBox(width: 8),
                PlayerSongActions(song: song, onLyrics: onLyrics, size: 40),
              ],
            ),
          ],
          const SizedBox(height: 8),
          PlayerSeekRow(song: song),
          if (!stacked) ...[const SizedBox(height: 4), const PlayerExtras()],
          const SizedBox(height: 8),
          transport,
          const SizedBox(height: 10),
          const PlayerModeDock(),
        ],
      ),
    );
    if (stacked) return SingleChildScrollView(child: content);
    // Scrolls inside the pane when even the compact version does not fit.
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// The Queue / Lyrics control and the page under it.
class _Panes extends ConsumerWidget {
  const _Panes({
    required this.tab,
    required this.lyricsOn,
    required this.onTab,
  });
  final TwoPaneTab tab;
  final bool lyricsOn;
  final ValueChanged<TwoPaneTab> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasLyrics =
        tab == TwoPaneTab.lyrics &&
        ref.watch(lyricsProvider.select((s) => s.lyrics.isNotEmpty));
    return Column(
      children: [
        if (lyricsOn)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _PaneTabs(selected: tab, onChanged: onTab),
                ),
                if (hasLyrics) ...[
                  const SizedBox(width: 8),
                  WvButton(
                    circular: true,
                    size: 38,
                    tooltip: 'Full screen',
                    onPressed: () => LyricsFullscreenPage.open(context),
                    child: const Icon(Icons.fullscreen_rounded),
                  ),
                  const SizedBox(width: 8),
                  WvButton(
                    primary: true,
                    circular: true,
                    size: 38,
                    tooltip: 'Share Card',
                    onPressed: () => _share(context, ref),
                    child: const Icon(Icons.ios_share_rounded),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: tab == TwoPaneTab.queue
              ? const PlayerQueuePage()
              : const LyricsView(
                  activeSize: 24,
                  inactiveSize: 18,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                ),
        ),
      ],
    );
  }

  void _share(BuildContext context, WidgetRef ref) {
    final song = ref.read(playerProvider).currentSong;
    if (song == null) return;
    AppNav.push(
      LyricCardGenerator(
        song: song,
        lyrics: ref.read(lyricsProvider).lyrics,
        themeColor: Wv.of(context).accentText,
      ),
    );
  }
}

/// Connected Aqua segments like the sheet's page switcher, with labels.
class _PaneTabs extends StatelessWidget {
  const _PaneTabs({required this.selected, required this.onChanged});
  final TwoPaneTab selected;
  final ValueChanged<TwoPaneTab> onChanged;

  static const _labels = {
    TwoPaneTab.queue: 'Queue',
    TwoPaneTab.lyrics: 'Lyrics',
  };
  static const _icons = {
    TwoPaneTab.queue: Icons.queue_music_rounded,
    TwoPaneTab.lyrics: Icons.lyrics_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    const tabs = TwoPaneTab.values;
    return Row(
      children: [
        for (int i = 0; i < tabs.length; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: selected == tabs[i],
              label: _labels[tabs[i]],
              excludeSemantics: true,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.horizontal(
                  left: i == 0 ? const Radius.circular(8) : Radius.zero,
                  right: i == tabs.length - 1
                      ? const Radius.circular(8)
                      : Radius.zero,
                ),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: a.gelGradient(primary: selected == tabs[i]),
                    border: Border.all(
                      color: selected == tabs[i]
                          ? Color.lerp(a.accent, Colors.black, 0.25)!
                          : a.outline.withValues(alpha: 0.7),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => onChanged(tabs[i]),
                    child: SizedBox(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _icons[tabs[i]],
                            size: 18,
                            color: selected == tabs[i] ? a.onAccent : a.text,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _labels[tabs[i]]!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected == tabs[i]
                                    ? a.onAccent
                                    : a.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The picker thumbnail: a square with bars on the left, list rows on the
/// right, in theme colors.
class TwoPaneLayoutPreview extends StatelessWidget {
  const TwoPaneLayoutPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return CustomPaint(
      painter: _TwoPanePainter(
        accent: a.accent,
        line: a.textSecondary,
        divider: a.separator,
        highlight: a.primaryContainer,
      ),
      size: Size.infinite,
    );
  }
}

class _TwoPanePainter extends CustomPainter {
  _TwoPanePainter({
    required this.accent,
    required this.line,
    required this.divider,
    required this.highlight,
  });
  final Color accent;
  final Color line;
  final Color divider;
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final split = w * 0.46;
    RRect rr(double x, double y, double rw, double rh, double r) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, rw, rh),
          Radius.circular(r),
        );
    final soft = Paint()..color = line.withValues(alpha: 0.35);
    final strong = Paint()..color = line.withValues(alpha: 0.6);
    // Left: the cover, the title bars, the seek bar and the play button.
    final cover = math.min(split - w * 0.16, h * 0.42);
    final lx = (split - cover) / 2;
    canvas.drawRRect(
      rr(lx, h * 0.1, cover, cover, 4),
      Paint()..color = accent.withValues(alpha: 0.75),
    );
    final bx = w * 0.08;
    final bw = split - w * 0.16;
    final by = h * 0.1 + cover + h * 0.06;
    canvas.drawRRect(rr(bx, by, bw * 0.7, h * 0.035, 2), strong);
    canvas.drawRRect(rr(bx, by + h * 0.06, bw * 0.45, h * 0.03, 2), soft);
    canvas.drawRRect(rr(bx, by + h * 0.13, bw, h * 0.025, 2), soft);
    canvas.drawRRect(
      rr(bx + bw * 0.3, by + h * 0.19, bw * 0.4, h * 0.07, h * 0.035),
      Paint()..color = accent,
    );
    // The divider.
    canvas.drawRect(Rect.fromLTWH(split, 0, 1, h), Paint()..color = divider);
    // Right: the list rows, the first one playing.
    final rx = split + w * 0.07;
    final rw = w - rx - w * 0.07;
    final rowH = h * 0.1;
    for (var i = 0; i < 5; i++) {
      final y = h * 0.1 + i * (rowH + h * 0.04);
      if (y + rowH > h) break;
      canvas.drawRRect(
        rr(rx, y, rw, rowH, 3),
        Paint()..color = i == 0 ? highlight : line.withValues(alpha: 0.12),
      );
      canvas.drawRRect(
        rr(rx + rowH * 0.2, y + rowH * 0.2, rowH * 0.6, rowH * 0.6, 2),
        i == 0 ? (Paint()..color = accent) : soft,
      );
      canvas.drawRRect(
        rr(rx + rowH * 1.1, y + rowH * 0.3, rw * 0.5, rowH * 0.18, 1),
        strong,
      );
      canvas.drawRRect(
        rr(rx + rowH * 1.1, y + rowH * 0.6, rw * 0.32, rowH * 0.14, 1),
        soft,
      );
    }
  }

  @override
  bool shouldRepaint(_TwoPanePainter old) =>
      old.accent != accent ||
      old.line != line ||
      old.divider != divider ||
      old.highlight != highlight;
}
