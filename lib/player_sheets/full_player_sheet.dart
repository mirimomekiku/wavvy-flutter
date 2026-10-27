import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/artist_info_provider.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/player_sheet_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/lyric_card.dart';
import 'package:wavvy/widgets/seekable_artwork.dart';
import 'package:wavvy/widgets/song_menu.dart';

class FullPlayerSheet extends ConsumerStatefulWidget {
  const FullPlayerSheet({super.key});

  @override
  ConsumerState<FullPlayerSheet> createState() => _FullPlayerSheetState();
}

class _FullPlayerSheetState extends ConsumerState<FullPlayerSheet> {
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final enableLyricsFetching = ref.watch(
      settingsProvider.select((s) => s.enableLyricsFetching),
    );
    final enableArtistInfoFetching = ref.watch(
      settingsProvider.select((s) => s.enableArtistInfoFetching),
    );

    {
      final song = ref.watch(playerProvider.select((s) => s.currentSong));
      if (song == null) return const SizedBox.shrink();

      final palette = ref.watch(paletteProvider);
      final seedColor = palette.playerColor ?? Theme.of(context).primaryColor;
      final mainTextColor = palette.playerTextColor;
      final subTextColor = mainTextColor.withValues(alpha: 0.7);
      final navBarColor = seedColor.darken(40);

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: navBarColor,
          systemNavigationBarIconBrightness: Brightness.light,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: palette.playerTextColor == Colors.black
              ? Brightness.dark
              : Brightness.light,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(Ds.radiusL),
              topRight: Radius.circular(Ds.radiusL),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [seedColor, seedColor.darken(15), navBarColor],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 24,
              bottom: MediaQuery.paddingOf(context).bottom,
            ),
            child: Scaffold(
              backgroundColor: Colors.transparent,

              // --- APP BAR (Shared) ---
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: GelButton(
                  circular: true,
                  size: 32,
                  tooltip: "Close",
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                centerTitle: true,
                title: Consumer(builder: (context, ref, _) {
                  switch (ref.watch(sheetPageIndexProvider)) {
                    case 1:
                      return Text(
                        "Playing Next",
                        style: TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      );
                    case 2:
                      return Text(
                        "Lyrics",
                        style: TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      );
                    case 3:
                      return Text(
                        "Artist",
                        style: TextStyle(
                          color: mainTextColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      );
                    default:
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "PLAYING FROM ALBUM",
                            style: TextStyle(
                              color: subTextColor,
                              fontSize: 10,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            song.album ?? "Single",
                            style: TextStyle(
                              color: mainTextColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      );
                  }
                }),
                actions: [
                  GelButton(
                    circular: true,
                    size: 32,
                    tooltip: "More",
                    child: const Icon(Icons.more_horiz_rounded),
                    onPressed: () {
                      SongMenuHelper.show(
                        context,
                        ref,
                        song,
                        options: const SongMenuOptions(
                          showDelete: true,
                          showCustomEqualizer: true,
                          showSystemEqualizer: true,
                          showSongInfo: true,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),

              // --- BODY (PageView) ---
              body: Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      scrollBehavior: const MaterialScrollBehavior(),
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (index) {
                        ref.read(sheetPageIndexProvider.notifier).set(index);
                        if (index == 2) {
                          ref
                              .read(artistInfoProvider.notifier)
                              .fetchArtistInfo(song.artist ?? "");
                        }
                      },
                      children: [
                        // Page 0: MAIN PLAYER
                        _buildPlayerPage(
                          context,
                          song,
                          screenWidth,
                          mainTextColor,
                          subTextColor,
                          seedColor,
                        ),

                        // Page 1: QUEUE
                        _buildQueuePage(
                          context,
                          mainTextColor,
                          subTextColor,
                          seedColor,
                        ),

                        // Page 2: LYRICS (LRCLib)
                        _buildLyricsPage(context),

                        // Page 3: ARTIST INFO (Genius)
                        _buildArtistPage(context, mainTextColor, subTextColor),
                      ],
                    ),
                  ),

                  // --- BOTTOM TABS ---
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: _buildTabs(
                      enableLyricsFetching,
                      enableArtistInfoFetching,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  // --- WIDGET BUILDERS ---

  Widget _buildTabs(bool showLyrics, bool showArtist) {
    final pages = <int>[0, 1, if (showLyrics) 2, if (showArtist) 3];
    const names = ["Player", "Queue", "Lyrics", "Artist"];

    return Consumer(builder: (context, ref, _) {
      final selected = pages.indexOf(ref.watch(sheetPageIndexProvider));
      return AquaSegmented(
        labels: [for (final p in pages) names[p]],
        selected: selected,
        onChanged: (i) => _pageController.animateToPage(
          pages[i],
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  Widget _buildPlayerPage(
    BuildContext context,
    SongModel song,
    double screenWidth,
    Color mainTextColor,
    Color subTextColor,
    Color activeColor,
  ) {
    final artworkSize = screenWidth - 64;
    final a = Aqua.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        children: [
          const Spacer(flex: 2),

          AquaPhotoFrame(
            child: AnimatedSeekableArtwork(
              song: song,
              size: artworkSize - 8,
              iconColor: subTextColor,
            ),
          ),

          const Spacer(flex: 3),

          // Title & Artist (LCD panel)
          SizedBox(
            width: double.infinity,
            child: AquaLcd(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: a.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist ?? "Unknown Artist",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: a.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Seek Bar
          Consumer(builder: (context, ref, _) {
            final totalDuration = ref.watch(durationProvider);
            final currentPosition = ref.watch(positionProvider);
            final max = totalDuration.inMilliseconds.toDouble();
            final current = currentPosition.inMilliseconds.toDouble();
            final sliderValue = (max > 0) ? current.clamp(0.0, max) : 0.0;

            return Column(
              children: [
                Slider(
                  min: 0,
                  max: max > 0 ? max : 1.0,
                  value: sliderValue,
                  onChanged: (val) => ref
                      .read(playerProvider.notifier)
                      .seek(Duration(milliseconds: val.toInt())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        PlayerUtils.formatDuration(currentPosition),
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        PlayerUtils.formatDuration(totalDuration),
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: 24),

          Consumer(builder: (context, ref, _) {
            final isShuffle = ref.watch(
              playerProvider.select((s) => s.isShuffleModeEnabled),
            );
            final isPlaying = ref.watch(
              playerProvider.select((s) => s.isPlaying),
            );
            final loopMode = ref.watch(playerProvider.select((s) => s.loopMode));
            final notifier = ref.read(playerProvider.notifier);

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GelButton(
                  circular: true,
                  size: 38,
                  tooltip: "Shuffle",
                  primary: isShuffle,
                  onPressed: notifier.toggleShuffle,
                  child: const Icon(Icons.shuffle_rounded),
                ),
                GelButton(
                  circular: true,
                  size: 52,
                  tooltip: "Previous",
                  onPressed: notifier.previous,
                  child: const Icon(Icons.skip_previous_rounded),
                ),
                GelButton(
                  circular: true,
                  primary: true,
                  size: 72,
                  tooltip: isPlaying ? "Pause" : "Play",
                  onPressed: notifier.togglePlay,
                  child: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                GelButton(
                  circular: true,
                  size: 52,
                  tooltip: "Next",
                  onPressed: notifier.next,
                  child: const Icon(Icons.skip_next_rounded),
                ),
                GelButton(
                  circular: true,
                  size: 38,
                  tooltip: "Repeat",
                  primary: loopMode != LoopMode.off,
                  onPressed: notifier.cycleLoopMode,
                  child: Icon(PlayerUtils.getLoopIcon(loopMode)),
                ),
              ],
            );
          }),

          const Spacer(flex: 3),
        ],
      ),
    );
  }

  Widget _buildQueuePage(
    BuildContext context,
    Color textColor,
    Color subTextColor,
    Color activeColor,
  ) {
    final a = Aqua.of(context);

    return Consumer(builder: (context, ref, _) {
      final queue = ref.watch(playerProvider.select((s) => s.queue));
      final currentIndex = ref.watch(
        playerProvider.select((s) => s.currentIndex),
      );

      final ScrollController scrollController = ScrollController();
      if (currentIndex > 0 && queue.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scrollController.hasClients) {}
        });
      }

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        decoration: BoxDecoration(
          color: a.background,
          borderRadius: BorderRadius.circular(Ds.radiusM),
          border: Border.all(color: a.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.builder(
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: queue.length,
          itemBuilder: (context, index) {
            final s = queue[index];
            final isPlaying = currentIndex == index;
            final primary = isPlaying ? Colors.white : a.text;
            final secondary = isPlaying
                ? Colors.white.withValues(alpha: 0.85)
                : a.textSecondary;

            return InkWell(
              splashFactory: NoSplash.splashFactory,
              onTap: () {
                if (currentIndex != index) {
                  final player = ref.read(audioPlayerProvider);
                  player.seek(Duration.zero, index: index);
                  player.play();
                }
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? null
                      : (index.isEven ? a.background : a.stripe),
                  gradient: isPlaying
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: a.selection,
                        )
                      : null,
                  border: isPlaying
                      ? Border(
                          top: BorderSide(color: a.selectionBorder),
                          bottom: BorderSide(color: a.selectionBorder),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        border: Border.all(color: a.frameBorder),
                      ),
                      child: QueryArtworkWidget(
                        id: s.id,
                        type: ArtworkType.AUDIO,
                        nullArtworkWidget: Container(
                          color: a.stripe,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: a.textSecondary,
                          ),
                        ),
                        artworkBorder: BorderRadius.zero,
                        artworkWidth: 40,
                        artworkHeight: 40,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: primary,
                              fontWeight: isPlaying
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            s.artist ?? "Unknown",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: secondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (isPlaying)
                      const Icon(
                        Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }

  Widget _buildLyricsPage(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final mainTextColor = ref.watch(
        paletteProvider.select((s) => s.playerTextColor),
      );
      final activeColor = mainTextColor.brighten(30);
      final lyricsState = ref.watch(lyricsProvider);
      final lyrics = lyricsState.lyrics;

      if (lyricsState.isLoading) {
        return Center(child: CircularProgressIndicator(color: mainTextColor));
      }

      if (lyrics.isEmpty) {
        return Center(
          child: Text(
            "No Lyrics found",
            style: TextStyle(
              color: mainTextColor.withValues(alpha: 0.5),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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
              bottom: 100,
            ),
            itemBuilder: (context, index) {
              final line = lyrics[index];
              final isActive = index == lyricsState.currentIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Text(
                  line.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive
                        ? activeColor
                        : mainTextColor.withValues(alpha: 0.4),
                    fontSize: isActive ? 24 : 18,
                    fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
              );
            },
          ),

          Positioned(
            bottom: 24,
            right: 24,
            child: GelButton(
              primary: true,
              size: 36,
              width: 140,
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
                      themeColor: activeColor,
                    ),
                  );
                }
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _buildArtistPage(
    BuildContext context,
    Color textColor,
    Color subTextColor,
  ) {
    final a = Aqua.of(context);
    return Consumer(builder: (context, ref, _) {
      final artistInfo = ref.watch(artistInfoProvider);
      final currentSong = ref.watch(
        playerProvider.select((s) => s.currentSong),
      );
      if (artistInfo.isLoading) {
        return Center(child: CircularProgressIndicator(color: textColor));
      }
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            AquaPhotoFrame(
              circular: true,
              child: artistInfo.imageUrl.isNotEmpty
                  ? Image.network(
                      artistInfo.imageUrl,
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (c, o, s) => Container(
                        width: 200,
                        height: 200,
                        color: a.stripe,
                        child: Icon(
                          Icons.person_rounded,
                          size: 80,
                          color: a.textSecondary,
                        ),
                      ),
                    )
                  : Container(
                      width: 200,
                      height: 200,
                      color: a.stripe,
                      child: Icon(
                        Icons.person_rounded,
                        size: 80,
                        color: a.textSecondary,
                      ),
                    ),
            ),

            const SizedBox(height: 32),
            Text(
              currentSong?.artist ?? "About the Artist",
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: a.background,
                borderRadius: BorderRadius.circular(Ds.radiusM),
                border: Border.all(color: a.border),
              ),
              child: Text(
                artistInfo.bio.isEmpty
                    ? "No information found."
                    : artistInfo.bio,
                style: TextStyle(color: a.text, fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      );
    });
  }
}
