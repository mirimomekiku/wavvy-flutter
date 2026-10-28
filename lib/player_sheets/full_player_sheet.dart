import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/player_sheets/artist_page.dart';
import 'package:wavvy/playback/ab_loop.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/player_sheet_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/lyric_card.dart';
import 'package:wavvy/widgets/seekable_artwork.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/widgets/status_message.dart';
import 'package:wavvy/screens/audio_effects/effects.screen.dart';

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
    final visible = [
      0,
      1,
      if (settings.enableLyricsFetching) 2,
      if (settings.enableArtistInfoFetching) 3,
    ];
    final page = ref.watch(sheetPageIndexProvider);
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
                  _NowPlayingPage(
                    song: song,
                    onLyrics: settings.enableLyricsFetching
                        ? () => goTo(2)
                        : null,
                    onArtist: settings.enableArtistInfoFetching
                        ? () => goTo(3)
                        : null,
                  ),
                  const _QueuePage(),
                  _buildLyricsPage(context),
                  _buildArtistPage(context),
                ],
              ),
            ),
            _SheetToolbar(bottomInset: navBar, child: nav),
          ],
        ),
      ),
    );
  }

  Widget _buildLyricsPage(BuildContext context) {
    final a = Wv.of(context);
    return Consumer(
      builder: (context, ref, _) {
        final lyricsState = ref.watch(lyricsProvider);
        final lyrics = lyricsState.lyrics;

        if (lyricsState.isLoading) {
          return const Center(child: AquaSpinner(size: 34));
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
                ? null
                : TextButton(
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
          );
        }

        final current = lyricsState.currentIndex;
        return Stack(
          children: [
            // Soft fade at the top and bottom so lines glide in and out.
            ShaderMask(
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
                stops: [0, 0.07, 0.92, 1],
              ).createShader(rect),
              child: ScrollablePositionedList.builder(
                itemCount: lyrics.length,
                physics: const BouncingScrollPhysics(),
                itemScrollController: ref.read(lyricsScrollControllerProvider),
                itemPositionsListener: ref.read(
                  lyricsPositionsListenerProvider,
                ),
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 120),
                itemBuilder: (context, index) {
                  final isActive = index == current;
                  final isPast = current >= 0 && index < current;
                  final color = isActive
                      ? a.accent
                      : a.textSecondary.withValues(alpha: isPast ? 0.4 : 0.75);
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => ref
                        .read(playerProvider.notifier)
                        .seek(lyrics[index].time),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 4,
                      ),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        style: TextStyle(
                          color: color,
                          fontSize: isActive ? 28 : 22,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          height: 1.3,
                          letterSpacing: -0.4,
                        ),
                        child: Text(lyrics[index].text),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              bottom: 16,
              right: 20,
              child: WvButton(
                primary: true,
                circular: true,
                size: 52,
                tooltip: 'Share Card',
                child: const Icon(Icons.ios_share_rounded),
                onPressed: () {
                  final song = ref.read(playerProvider).currentSong;
                  if (song != null) {
                    AppNav.push(
                      LyricCardGenerator(
                        song: song,
                        lyrics: lyrics,
                        themeColor: a.accentText,
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildArtistPage(BuildContext context) => const ArtistInfoPage();
}

/// The Player tab: artwork, title row, seek bar, transport and mode dock.
class _NowPlayingPage extends ConsumerWidget {
  const _NowPlayingPage({required this.song, this.onLyrics, this.onArtist});
  final SongModel song;
  final VoidCallback? onLyrics;
  final VoidCallback? onArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final state = ref.watch(playerProvider);
    final controls = ref.read(playerProvider.notifier);
    final canNext =
        state.currentIndex < state.queue.length - 1 ||
        state.loopMode == LoopMode.all;
    return LayoutBuilder(
      builder: (context, c) {
        final width = math.min(c.maxWidth, 480.0) - 32;
        // Room for everything under the artwork: title, seek bar, the extras
        // row, transport and the mode dock.
        final side = math.min(width, math.max(140.0, c.maxHeight - 384));
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
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: a.text,
                                    height: 1.15,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: onArtist,
                                  child: Text(
                                    song.artist ?? 'Unknown Artist',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: a.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _FavoriteButton(song: song),
                          if (onLyrics != null) ...[
                            const SizedBox(width: 10),
                            WvButton(
                              circular: true,
                              squircle: true,
                              size: 44,
                              tooltip: 'View lyrics',
                              onPressed: onLyrics,
                              child: const Icon(Icons.lyrics_outlined),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      _SeekRow(song: song),
                      const SizedBox(height: 6),
                      const _PlaybackExtras(),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: WvButton(
                              size: 60,
                              tooltip: 'Previous',
                              onPressed: state.currentIndex > 0
                                  ? controls.previous
                                  : null,
                              child: const Icon(
                                Icons.skip_previous_rounded,
                                size: 30,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          WvButton(
                            primary: true,
                            width: 88,
                            size: 68,
                            tooltip: state.isPlaying ? 'Pause' : 'Play',
                            onPressed: controls.togglePlay,
                            child: Icon(
                              state.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 34,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: WvButton(
                              size: 60,
                              tooltip: 'Next',
                              onPressed: canNext ? controls.next : null,
                              child: const Icon(
                                Icons.skip_next_rounded,
                                size: 30,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: a.surfaceHigh,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: a.outline.withValues(alpha: 0.65),
                          ),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              _ModeCell(
                                tooltip: state.isShuffleModeEnabled
                                    ? 'Shuffle on'
                                    : 'Shuffle',
                                selected: state.isShuffleModeEnabled,
                                icon: Icons.shuffle_rounded,
                                onPressed: controls.toggleShuffle,
                              ),
                              VerticalDivider(width: 1, color: a.separator),
                              _ModeCell(
                                tooltip: state.loopMode == LoopMode.off
                                    ? 'Repeat'
                                    : 'Repeat ${state.loopMode.name}',
                                selected: state.loopMode != LoopMode.off,
                                icon: PlayerUtils.getLoopIcon(state.loopMode),
                                onPressed: controls.cycleLoopMode,
                              ),
                              VerticalDivider(width: 1, color: a.separator),
                              _ModeCell(
                                tooltip: 'Sound',
                                selected: false,
                                icon: Icons.tune_rounded,
                                onPressed: () =>
                                    AppNav.push(const AudioEffectsScreen()),
                              ),
                            ],
                          ),
                        ),
                      ),
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

/// Icon-only page switcher (Player / Queue / Lyrics / About) drawn as a
/// connected Aqua segmented control: gel segments, blue when selected.
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
  ];
  static const _tips = ['Player', 'Queue', 'Lyrics', 'About'];

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

class _ModeCell extends StatelessWidget {
  const _ModeCell({
    required this.tooltip,
    required this.selected,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final bool selected;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: selected,
          label: tooltip,
          excludeSemantics: true,
          child: InkWell(
            onTap: onPressed,
            child: Container(
              height: 48,
              color: selected ? a.primaryContainer : Colors.transparent,
              child: Icon(
                icon,
                size: 22,
                color: selected ? a.onPrimaryContainer : a.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The heart: adds the playing song to Favorites, or takes it out.
class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.song});
  final SongModel song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(
      favoritesProvider.select((f) => f.containsKey(song.id)),
    );
    return WvButton(
      circular: true,
      squircle: true,
      size: 44,
      tooltip: liked ? 'Remove from Favorites' : 'Add to Favorites',
      onPressed: () => ref.read(favoritesProvider.notifier).toggle(song),
      child: Icon(
        liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: liked ? const Color(0xFFD8453B) : null,
      ),
    );
  }
}

/// Skip back or forward 15 seconds, and mark a section to repeat (A-B).
class _PlaybackExtras extends ConsumerWidget {
  const _PlaybackExtras();

  static const _skip = Duration(seconds: 15);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(abLoopProvider);
    final controls = ref.read(playerProvider.notifier);
    final label = loop.isActive
        ? 'A\u2013B on'
        : loop.start != null
        ? 'Set B'
        : 'A\u2013B';
    final tooltip = loop.isActive
        ? 'Clear the repeated section'
        : loop.start != null
        ? 'Mark the end of the section to repeat'
        : 'Mark the start of a section to repeat';
    return Row(
      children: [
        Expanded(
          child: WvButton(
            size: 34,
            tooltip: 'Back 15 seconds',
            onPressed: () => controls.seek(-_skip, relative: true),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.replay_rounded, size: 16),
                SizedBox(width: 4),
                Text('15'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: WvButton(
            key: const Key('ab_loop'),
            size: 34,
            primary: loop.start != null,
            tooltip: tooltip,
            onPressed: () => ref
                .read(abLoopProvider.notifier)
                .press(ref.read(positionProvider)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.repeat_one_rounded, size: 16),
                const SizedBox(width: 4),
                Text(label),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WvButton(
            size: 34,
            tooltip: 'Forward 15 seconds',
            onPressed: () => controls.seek(_skip, relative: true),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('15'),
                SizedBox(width: 4),
                Icon(Icons.refresh_rounded, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Aqua seek bar with elapsed/total time and a bitrate/format readout.
class _SeekRow extends ConsumerWidget {
  const _SeekRow({required this.song});
  final SongModel song;

  String get _format {
    // Raw media-store rows can lack these; the readout is optional.
    String ext = '';
    int kbps = 0;
    try {
      ext = song.fileExtension.trim().toUpperCase();
      final ms = song.duration ?? 0;
      kbps = ms > 0 ? (song.size * 8 / ms).round() : 0;
    } catch (_) {}
    return [if (kbps > 0) '$kbps kbps', if (ext.isNotEmpty) ext].join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final duration = ref.watch(durationProvider);
    final position = ref.watch(positionProvider);
    final controls = ref.read(playerProvider.notifier);
    final max = math.max(1.0, duration.inMilliseconds.toDouble());
    final format = _format;
    final loop = ref.watch(abLoopProvider);
    // Elapsed and total time sit in recessed LCD readouts, as on a Mac.
    Widget lcd(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: a.lcdDecoration.copyWith(
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: a.text,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return Column(
      children: [
        AquaSeekBar(
          value: position.inMilliseconds.toDouble().clamp(0.0, max),
          max: max,
          step: 5000,
          loopStart: loop.start?.inMilliseconds.toDouble(),
          loopEnd: loop.end?.inMilliseconds.toDouble(),
          onChanged: (v) {
            if (duration > Duration.zero) {
              controls.seek(Duration(milliseconds: v.toInt()));
            }
          },
        ),
        Row(
          children: [
            lcd(PlayerUtils.formatDuration(position)),
            Expanded(
              child: Center(
                child: format.isEmpty
                    ? null
                    : Text(
                        format,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: a.textSecondary),
                      ),
              ),
            ),
            lcd(PlayerUtils.formatDuration(duration)),
          ],
        ),
      ],
    );
  }
}

class _QueuePage extends ConsumerWidget {
  const _QueuePage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final state = ref.watch(playerProvider);
    final queue = state.queue;
    final controls = ref.read(playerProvider.notifier);
    final totalMs = queue.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final hasUpcoming = state.currentIndex < queue.length - 1;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Up next',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: a.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${queue.length} ${queue.length == 1 ? 'track' : 'tracks'}'
                      ' \u00b7 ${PlayerUtils.formatDuration(Duration(milliseconds: totalMs))}',
                      style: TextStyle(fontSize: 12, color: a.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              WvButton(
                size: 38,
                width: 112,
                tooltip: 'Clear upcoming',
                onPressed: hasUpcoming ? controls.clearUpcoming : null,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.playlist_remove_rounded),
                    SizedBox(width: 6),
                    Text('Clear'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            buildDefaultDragHandles: false,
            itemCount: queue.length,
            onReorderItem: controls.moveQueueItem,
            itemExtent: math.max(
              76.0,
              MediaQuery.textScalerOf(context).scale(40) + 36,
            ),
            itemBuilder: (context, index) {
              final song = queue[index];
              final current = state.currentIndex == index;
              return Padding(
                key: ValueKey('queue-$index-${song.id}'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Material(
                  color: current ? a.primaryContainer : a.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: current
                          ? a.accent.withValues(alpha: 0.55)
                          : a.separator,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      if (!current) {
                        ref
                            .read(audioPlayerProvider)
                            .seek(Duration.zero, index: index);
                        ref.read(audioPlayerProvider).play();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                      child: Row(
                        children: [
                          WvArtwork(
                            radius: 8,
                            child: wvArtwork(
                              context,
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              size: 44,
                              placeholder: Icons.music_note_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: current
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: current
                                        ? a.onPrimaryContainer
                                        : a.text,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  song.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: current
                                        ? a.onPrimaryContainer.withValues(
                                            alpha: 0.75,
                                          )
                                        : a.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (current)
                            Icon(
                              Icons.graphic_eq_rounded,
                              size: 20,
                              color: a.accent,
                            ),
                          IconButton(
                            tooltip: 'Remove from queue',
                            onPressed: () => controls.removeFromQueue(index),
                            icon: Icon(
                              Icons.close_rounded,
                              color: a.textSecondary,
                              size: 18,
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Semantics(
                              label: 'Reorder ${song.title}',
                              child: SizedBox(
                                width: 32,
                                height: 48,
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 22,
                                  color: a.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
