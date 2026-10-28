import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/player_sheets/artist_page.dart';
import 'package:wavvy/downloader/flavor.dart';
import 'package:wavvy/player_sheets/layouts/player_layout.dart';
import 'package:wavvy/player_sheets/layouts/two_pane_layout.dart';
import 'package:wavvy/player_sheets/lyrics_page.dart';
import 'package:wavvy/player_sheets/queue_page.dart';
import 'package:wavvy/player_sheets/visualizer_page.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/player_sheet_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// The pages the player sheet shows, by index: 0 Player, 1 Queue, 2 Lyrics,
/// 3 About, 4 Visualizer. Lyrics, About and Visualizer follow their settings,
/// and the Visualizer is not in the Play build at all. With
/// [embedsQueueAndLyrics] (the two-pane layout on a wide screen shows them
/// beside the player) the Queue and Lyrics pages are left out of the switcher.
List<int> playerSheetPages(
  SettingsState settings, {
  bool embedsQueueAndLyrics = false,
}) => [
  0,
  if (!embedsQueueAndLyrics) 1,
  if (!embedsQueueAndLyrics && settings.enableLyricsFetching) 2,
  if (settings.enableArtistInfoFetching) 3,
  if (kVisualizerAvailable && settings.enableVisualizer) 4,
];

class FullPlayerSheet extends ConsumerStatefulWidget {
  const FullPlayerSheet({super.key, this.initialPage = 0});
  final int initialPage;
  @override
  ConsumerState<FullPlayerSheet> createState() => _FullPlayerSheetState();
}

class _FullPlayerSheetState extends ConsumerState<FullPlayerSheet> {
  late final PageController _pages = PageController(
    initialPage: widget.initialPage,
  );
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final settings = ref.watch(settingsProvider);
    final size = MediaQuery.sizeOf(context);
    final embeds =
        resolvePlayerLayout(settings, size) == PlayerLayout.twoPane &&
        isWidePlayerScreen(size);
    final visible = playerSheetPages(settings, embedsQueueAndLyrics: embeds);
    final page = ref.watch(sheetPageIndexProvider);
    if (embeds && (page == 1 || page == 2)) {
      // Rotated (or opened) on a page that now lives beside the player: show
      // the player with that pane chosen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pages.hasClients) return;
        ref
            .read(twoPaneTabProvider.notifier)
            .set(page == 2 ? TwoPaneTab.lyrics : TwoPaneTab.queue);
        _pages.jumpToPage(0);
      });
    }
    final statusBar = math.max(
      MediaQuery.paddingOf(context).top,
      MediaQueryData.fromView(View.of(context)).padding.top,
    );
    void goTo(int i) => _pages.animateToPage(
      i,
      duration: Ds.medium,
      curve: Curves.easeOutCubic,
    );
    final navBar = math.max(
      MediaQuery.paddingOf(context).bottom,
      MediaQueryData.fromView(View.of(context)).padding.bottom,
    );
    final nav = _SheetNav(page: page, pages: visible, onSelect: goTo);
    return WvSystemUi(
      child: Material(
        color: a.pageColor,
        // The modal route strips the top inset from MediaQuery, so read it from
        // the window; the header paints behind the status bar and is padded.
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: a.chromeGradient,
                image: a.chromeGrain,
                border: Border(bottom: BorderSide(color: a.separator)),
              ),
              padding: EdgeInsets.fromLTRB(8, 4 + statusBar, 8, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  Expanded(
                    child: Text(
                      'Now Playing',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: a.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'More',
                    onPressed: () => SongMenuHelper.show(
                      context,
                      ref,
                      song,
                      options: const SongMenuOptions(
                        showDelete: true,
                        showCustomEqualizer: true,
                        showSystemEqualizer: true,
                        showSongInfo: true,
                        showPlaybackSpeed: true,
                      ),
                    ),
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) =>
                    ref.read(sheetPageIndexProvider.notifier).set(index),
                children: [
                  PlayerLayoutHost(
                    data: PlayerLayoutData(
                      song: song,
                      onLyrics: settings.enableLyricsFetching
                          ? () => goTo(2)
                          : null,
                      onArtist: settings.enableArtistInfoFetching
                          ? () => goTo(3)
                          : null,
                      onQueue: () => goTo(1),
                    ),
                  ),
                  const PlayerQueuePage(),
                  const PlayerLyricsPage(),
                  _buildArtistPage(context),
                  // Last, so the other pages keep their indices.
                  if (kVisualizerAvailable && settings.enableVisualizer)
                    VisualizerPage(song: song, active: page == 4),
                ],
              ),
            ),
            _SheetToolbar(bottomInset: navBar, child: nav),
          ],
        ),
      ),
    );
  }

  Widget _buildArtistPage(BuildContext context) => const ArtistInfoPage();
}

/// Brushed-metal bottom toolbar, like the bar under a Mac OS X window.
class _SheetToolbar extends StatelessWidget {
  const _SheetToolbar({required this.child, required this.bottomInset});
  final Widget child;

  /// System navigation bar height; the toolbar paints behind it.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: a.chromeGradient,
        image: a.chromeGrain,
        border: Border(
          top: BorderSide(color: a.outline.withValues(alpha: 0.55)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: a.dark ? 0.04 : 0.7),
            offset: const Offset(0, -1),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottomInset),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: child,
        ),
      ),
    );
  }
}

/// Icon-only page switcher (Player / Queue / Lyrics / About / Visualizer)
/// drawn as a connected Aqua segmented control: gel segments, blue when selected.
class _SheetNav extends StatelessWidget {
  const _SheetNav({
    required this.page,
    required this.pages,
    required this.onSelect,
  });
  final int page;
  final List<int> pages;
  final ValueChanged<int> onSelect;

  static const _icons = [
    Icons.album_rounded,
    Icons.queue_music_rounded,
    Icons.lyrics_rounded,
    Icons.person_rounded,
    Icons.equalizer_rounded,
  ];
  static const _tips = ['Player', 'Queue', 'Lyrics', 'About', 'Visualizer'];

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Row(
      children: [
        for (int i = 0; i < pages.length; i++)
          Expanded(
            child: Tooltip(
              message: _tips[pages[i]],
              child: Semantics(
                button: true,
                selected: page == pages[i],
                label: _tips[pages[i]],
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.horizontal(
                    left: i == 0 ? const Radius.circular(8) : Radius.zero,
                    right: i == pages.length - 1
                        ? const Radius.circular(8)
                        : Radius.zero,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: a.gelGradient(primary: page == pages[i]),
                      border: Border(
                        top: BorderSide(
                          color: page == pages[i]
                              ? Color.lerp(a.accent, Colors.black, 0.25)!
                              : a.outline.withValues(alpha: 0.7),
                        ),
                        bottom: BorderSide(
                          color: page == pages[i]
                              ? Color.lerp(a.accent, Colors.black, 0.25)!
                              : a.outline.withValues(alpha: 0.7),
                        ),
                        left: BorderSide(
                          color: i == 0 || page == pages[i]
                              ? (page == pages[i]
                                    ? Color.lerp(a.accent, Colors.black, 0.25)!
                                    : a.outline.withValues(alpha: 0.7))
                              : Colors.transparent,
                        ),
                        right: BorderSide(
                          color: page == pages[i]
                              ? Color.lerp(a.accent, Colors.black, 0.25)!
                              : a.outline.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    child: InkWell(
                      onTap: () => onSelect(pages[i]),
                      child: SizedBox(
                        height: 40,
                        child: Icon(
                          _icons[pages[i]],
                          size: 22,
                          color: page == pages[i] ? a.onAccent : a.text,
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
  }
}
