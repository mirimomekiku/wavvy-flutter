import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/artist_info_provider.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/player_sheet_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/lyric_card.dart';
import 'package:wavvy/widgets/seekable_artwork.dart';
import 'package:wavvy/widgets/song_menu.dart';
import 'package:wavvy/widgets/audio_dialogs.dart';
import 'package:wavvy/widgets/wv_song_list.dart';
import 'package:wavvy/widgets/status_message.dart';
import 'package:wavvy/player_sheets/player_dialogs.dart';
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
    const labels = ['Player', 'Queue', 'Lyrics', 'Artist'];
    final page = ref.watch(sheetPageIndexProvider);
    return WvSystemUi(
      child: Material(
        color: a.background,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: a.chromeGradient,
                  border: Border(bottom: BorderSide(color: a.separator)),
                ),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'NOW PLAYING',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w600,
                              color: a.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            song.album ?? 'Your library',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: a.text),
                          ),
                        ],
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: WvChips(
                  labels: [for (final i in visible) labels[i]],
                  selected: visible.indexOf(page),
                  onChanged: (i) => _pages.animateToPage(
                    visible[i],
                    duration: Ds.medium,
                    curve: Curves.easeOutCubic,
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) =>
                      ref.read(sheetPageIndexProvider.notifier).set(index),
                  children: [
                    _record(song),
                    const _QueuePage(),
                    _buildLyricsPage(context),
                    _buildArtistPage(context),
                  ],
                ),
              ),
              _PlayerDock(compactTitle: page != 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _record(SongModel song) {
    final a = Wv.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final side = math.min(
          c.maxWidth - 56,
          math.max(160.0, c.maxHeight - 122),
        );
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 22),
                Text(
                  song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    color: a.text,
                    height: 1.15,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  song.artist ?? 'Unknown Artist',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: a.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLyricsPage(BuildContext context) {
    final a = Wv.of(context);
    return Consumer(
      builder: (context, ref, _) {
        final lyricsState = ref.watch(lyricsProvider);
        final lyrics = lyricsState.lyrics;

        if (lyricsState.isLoading) {
          return const Center(child: PixelLoader(size: 36));
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

        return Stack(
          children: [
            ScrollablePositionedList.builder(
              itemCount: lyrics.length,
              physics: const BouncingScrollPhysics(),
              itemScrollController: ref.read(lyricsScrollControllerProvider),
              itemPositionsListener: ref.read(lyricsPositionsListenerProvider),
              padding: const EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: 110,
              ),
              itemBuilder: (context, index) {
                final line = lyrics[index];
                final isActive = index == lyricsState.currentIndex;
                return InkWell(
                  onTap: () =>
                      ref.read(playerProvider.notifier).seek(line.time),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      line.text,
                      style: TextStyle(
                        color: isActive ? a.accent : a.textSecondary,
                        fontSize: 26,
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                        height: 1.4,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              bottom: 16,
              right: 24,
              child: WvButton(
                primary: true,
                width: 160,
                size: 48,
                tooltip: "Share Card",
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.ios_share_rounded, size: 18),
                    SizedBox(width: 6),
                    Text("Share Card"),
                  ],
                ),
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

  Widget _buildArtistPage(BuildContext context) {
    final a = Wv.of(context);
    return Consumer(
      builder: (context, ref, _) {
        final artistInfo = ref.watch(artistInfoProvider);
        final currentSong = ref.watch(
          playerProvider.select((s) => s.currentSong),
        );
        if (artistInfo.isLoading) {
          return const Center(child: PixelLoader(size: 36));
        }
        Widget placeholder() => WvMediaPlaceholder(
          seed: currentSong?.artistId ?? currentSong?.id ?? 0,
          size: 200,
        );
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: WvArtwork(
                  circular: true,
                  elevated: true,
                  child: artistInfo.imageUrl.isNotEmpty
                      ? Image.network(
                          artistInfo.imageUrl,
                          width: 200,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (c, o, s) => placeholder(),
                        )
                      : placeholder(),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                currentSong?.artist ?? "About the Artist",
                style: TextStyle(
                  color: a.text,
                  fontSize: 24,
                  fontFamily: 'WorkSans',
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 12),
              WvPanel(
                padding: const EdgeInsets.all(20),
                color: a.tertiaryContainer,
                radius: 14,
                child: Text(
                  artistInfo.bio.isEmpty
                      ? "No information found."
                      : artistInfo.bio,
                  style: TextStyle(
                    color: a.onTertiaryContainer,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

/// The "Playing Next" list. Owns its ScrollController so the scroll position
/// survives rebuilds, and keeps the playing track in view.
class _PlayerDock extends ConsumerWidget {
  const _PlayerDock({required this.compactTitle});
  final bool compactTitle;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final shortScreen = MediaQuery.sizeOf(context).height < 520;
    final state = ref.watch(playerProvider);
    final controls = ref.read(playerProvider.notifier);
    return Container(
      decoration: BoxDecoration(
        gradient: a.chromeGradient,
        border: Border(top: BorderSide(color: a.separator)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compactTitle)
            Text(
              state.currentSong?.title ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: a.textSecondary),
            ),
          Consumer(
            builder: (context, ref, _) {
              final duration = ref.watch(durationProvider);
              final position = ref.watch(positionProvider);
              final max = math.max(1.0, duration.inMilliseconds.toDouble());
              return Column(
                children: [
                  SizedBox(
                    height: 30,
                    child: Slider(
                      value: position.inMilliseconds.toDouble().clamp(0.0, max),
                      max: max,
                      label: PlayerUtils.formatDuration(position),
                      onChanged: duration > Duration.zero
                          ? (v) =>
                                controls.seek(Duration(milliseconds: v.toInt()))
                          : null,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        PlayerUtils.formatDuration(position),
                        style: TextStyle(fontSize: 10, color: a.textSecondary),
                      ),
                      Text(
                        PlayerUtils.formatDuration(duration),
                        style: TextStyle(fontSize: 10, color: a.textSecondary),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: state.isShuffleModeEnabled ? 'Shuffle on' : 'Shuffle',
                isSelected: state.isShuffleModeEnabled,
                onPressed: controls.toggleShuffle,
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: state.isShuffleModeEnabled
                      ? a.accent
                      : a.textSecondary,
                  size: 21,
                ),
              ),
              IconButton(
                tooltip: 'Previous',
                onPressed: state.currentIndex > 0 ? controls.previous : null,
                icon: const Icon(Icons.skip_previous_rounded, size: 29),
              ),
              WvButton(
                primary: true,
                circular: true,
                size: shortScreen ? 48 : 58,
                tooltip: state.isPlaying ? 'Pause' : 'Play',
                onPressed: controls.togglePlay,
                child: Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 32,
                ),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed:
                    state.currentIndex < state.queue.length - 1 ||
                        state.loopMode == LoopMode.all
                    ? controls.next
                    : null,
                icon: const Icon(Icons.skip_next_rounded, size: 29),
              ),
              IconButton(
                tooltip: state.loopMode == LoopMode.off
                    ? 'Repeat'
                    : 'Repeat ${state.loopMode.name}',
                onPressed: controls.cycleLoopMode,
                icon: Icon(
                  PlayerUtils.getLoopIcon(state.loopMode),
                  color: state.loopMode != LoopMode.off
                      ? a.accent
                      : a.textSecondary,
                  size: 21,
                ),
              ),
            ],
          ),
          if (!shortScreen)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => showSpeedDialog(ref),
                  icon: const Icon(Icons.speed_rounded, size: 16),
                  label: const Text('Speed', style: TextStyle(fontSize: 11)),
                ),
                TextButton.icon(
                  onPressed: () => openSleepTimerDialog(ref),
                  icon: Icon(
                    state.sleepTimerMinutes == null
                        ? Icons.bedtime_outlined
                        : Icons.bedtime_rounded,
                    size: 16,
                  ),
                  label: Text(
                    state.sleepTimerMinutes == null
                        ? 'Sleep timer'
                        : '${state.sleepTimerMinutes} min',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => AppNav.push(const AudioEffectsScreen()),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: const Text('Sound', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
        ],
      ),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Up next \u00b7 ${queue.length} tracks',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: a.text,
                  ),
                ),
              ),
              Flexible(
                child: TextButton(
                  onPressed: state.currentIndex < queue.length - 1
                      ? controls.clearUpcoming
                      : null,
                  child: const Text(
                    'Clear upcoming',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11),
                  ),
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
              72.0,
              MediaQuery.textScalerOf(context).scale(40) + 32,
            ),
            itemBuilder: (context, index) {
              final song = queue[index];
              final current = state.currentIndex == index;
              return Material(
                key: ValueKey('queue-$index-${song.id}'),
                color: current
                    ? a.primaryContainer
                    : index.isOdd
                    ? a.stripe
                    : a.surface,
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        WvArtwork(
                          radius: 6,
                          child: wvArtwork(
                            context,
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            size: 40,
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
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: a.text,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                song.artist ?? 'Unknown Artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: a.textSecondary,
                                ),
                              ),
                            ],
                          ),
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
                              width: 28,
                              height: 48,
                              child: Icon(
                                Icons.drag_handle_rounded,
                                size: 20,
                                color: a.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
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
