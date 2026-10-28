import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/player_sheets/lyrics_fullscreen.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/lyric_card.dart';
import 'package:wavvy/widgets/status_message.dart';

/// The Lyrics page of the player sheet: synced lines, full screen and share.
class PlayerLyricsPage extends StatelessWidget {
  const PlayerLyricsPage({super.key});

  @override
  Widget build(BuildContext context) {
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
              left: 20,
              child: WvButton(
                circular: true,
                size: 52,
                tooltip: 'Full screen',
                child: const Icon(Icons.fullscreen_rounded),
                onPressed: () => LyricsFullscreenPage.open(context),
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
}
