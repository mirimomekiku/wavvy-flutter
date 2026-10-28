import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/status_message.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// Bounds and step of the full-screen lyrics text size (a factor on the base
/// size, on top of the system text scale).
const double kLyricsScaleMin = 0.8;
const double kLyricsScaleMax = 1.8;
const double kLyricsScaleStep = 0.1;
const String kLyricsScaleKey = 'lyrics_fullscreen_scale';

/// The size factor of the full-screen lyrics, remembered between sessions.
final lyricsFullscreenScaleProvider =
    NotifierProvider<LyricsFullscreenScale, double>(LyricsFullscreenScale.new);

class LyricsFullscreenScale extends Notifier<double> {
  @override
  double build() {
    unawaited(_load());
    return 1;
  }

  static double _bounded(double v) =>
      ((v / kLyricsScaleStep).round() * kLyricsScaleStep).clamp(
        kLyricsScaleMin,
        kLyricsScaleMax,
      );

  Future<void> _load() async {
    try {
      final stored = await SharedPreferencesAsync().getDouble(kLyricsScaleKey);
      if (stored != null && stored.isFinite) state = _bounded(stored);
    } catch (e) {
      debugPrint('could not read the lyrics size: $e');
    }
  }

  /// Makes the text one step larger or smaller, within the bounds.
  void step(int direction) {
    final next = _bounded(state + direction * kLyricsScaleStep);
    if (next == state) return;
    state = next;
    unawaited(
      SharedPreferencesAsync().setDouble(kLyricsScaleKey, next).catchError((
        Object e,
      ) {
        debugPrint('could not save the lyrics size: $e');
      }),
    );
  }
}

/// Keeps the screen on (true) or hands it back (false). Overridden in tests.
final lyricsScreenAwakeProvider = Provider<void Function(bool)>(
  (ref) => (on) {
    unawaited(
      WakelockPlus.toggle(enable: on).catchError((Object e) {
        debugPrint('wakelock failed: $e');
      }),
    );
  },
);

/// Synced lyrics shown large and centered over the whole screen: the current
/// line stands out, the others are dimmed, and a tap on a line seeks to it.
/// Opened from the Lyrics tab of the player sheet.
///
/// It has its own scroll controller and follows `lyricsProvider`'s current
/// line itself, so it never competes with the sheet's list (which the
/// coordinator drives through `lyricsScrollControllerProvider`).
class LyricsFullscreenPage extends ConsumerStatefulWidget {
  const LyricsFullscreenPage({super.key});

  /// Pushes the page over the player sheet with a short fade.
  static Future<void> open(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'lyrics_fullscreen'),
        transitionDuration: still
            ? Duration.zero
            : const Duration(milliseconds: 260),
        reverseTransitionDuration: still
            ? Duration.zero
            : const Duration(milliseconds: 200),
        pageBuilder: (_, _, _) => const LyricsFullscreenPage(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  ConsumerState<LyricsFullscreenPage> createState() =>
      _LyricsFullscreenPageState();
}

class _LyricsFullscreenPageState extends ConsumerState<LyricsFullscreenPage> {
  final ItemScrollController _scroll = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  late final void Function(bool) _awake = ref.read(lyricsScreenAwakeProvider);
  // A State's ref is gone by dispose(), so keep what leaving needs.
  late final ProviderContainer _container;

  /// Where the current line sits, as a fraction of the height from the top.
  static const _anchor = 0.4;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    _awake(true);
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    // Back to whatever Settings asks for, not simply off.
    _awake(_container.read(settingsProvider).enableWakeLock);
    super.dispose();
  }

  /// Brings [index] to the anchor: smoothly, or at once with reduced motion.
  void _follow(int index) {
    final count = ref.read(lyricsProvider).lyrics.length;
    if (index < 0 || index >= count || !_scroll.isAttached) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(index: index, alignment: _anchor);
    } else {
      _scroll.scrollTo(
        index: index,
        alignment: _anchor,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final lyricsState = ref.watch(lyricsProvider);
    final scale = ref.watch(lyricsFullscreenScaleProvider);

    ref.listen(lyricsProvider.select((s) => s.currentIndex), (_, index) {
      _follow(index);
    });
    // Larger or smaller lines change their heights; keep the current one put.
    ref.listen(lyricsFullscreenScaleProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow(ref.read(lyricsProvider).currentIndex);
      });
    });

    final style = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: a.dark ? Brightness.light : Brightness.dark,
      systemNavigationBarIconBrightness: a.dark
          ? Brightness.light
          : Brightness.dark,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: Scaffold(
        backgroundColor: a.pageColor,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (song != null) _Backdrop(song: song),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(song: song, scale: scale),
                  Expanded(child: _body(context, lyricsState, scale, song)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    LyricsState lyricsState,
    double scale,
    SongModel? song,
  ) {
    final lyrics = lyricsState.lyrics;
    if (lyricsState.isLoading) {
      return const Center(child: AquaSpinner(size: 34));
    }
    if (lyrics.isEmpty) {
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
    // Lyrics without timestamps arrive as one block at time zero.
    if (lyrics.length == 1 && lyrics.first.time == Duration.zero) {
      return _PlainLyrics(text: lyrics.first.text, scale: scale);
    }
    return _SyncedLyrics(
      lyrics: lyrics,
      current: lyricsState.currentIndex,
      scale: scale,
      controller: _scroll,
      positions: _positions,
      anchor: _anchor,
      onSeek: (time) => ref.read(playerProvider.notifier).seek(time),
    );
  }
}

/// The blurred album art, washed with the page color so text stays readable
/// in light and dark, and tinted with the album color when there is one.
class _Backdrop extends ConsumerWidget {
  const _Backdrop({required this.song});
  final SongModel song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final tint = ref.watch(paletteProvider.select((p) => p.playerColor));
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
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
            ColoredBox(
              color: a.pageColor.withValues(alpha: a.dark ? 0.8 : 0.86),
            ),
            if (tint != null) ColoredBox(color: tint.withValues(alpha: 0.16)),
          ],
        ),
      ),
    );
  }
}

/// Text size buttons, the song, and the way out.
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.song, required this.scale});
  final SongModel? song;
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final sizes = ref.read(lyricsFullscreenScaleProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Smaller text',
            onPressed: scale > kLyricsScaleMin + 1e-6
                ? () => sizes.step(-1)
                : null,
            icon: const Icon(Icons.text_decrease_rounded),
          ),
          IconButton(
            tooltip: 'Larger text',
            onPressed: scale < kLyricsScaleMax - 1e-6
                ? () => sizes.step(1)
                : null,
            icon: const Icon(Icons.text_increase_rounded),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: a.text,
                  ),
                ),
                if (song != null)
                  Text(
                    song!.artist ?? 'Unknown Artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: a.textSecondary),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Exit full screen',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.fullscreen_exit_rounded),
          ),
        ],
      ),
    );
  }
}

class _SyncedLyrics extends StatelessWidget {
  const _SyncedLyrics({
    required this.lyrics,
    required this.current,
    required this.scale,
    required this.controller,
    required this.positions,
    required this.anchor,
    required this.onSeek,
  });
  final List<Lyric> lyrics;
  final int current;
  final double scale;
  final ItemScrollController controller;
  final ItemPositionsListener positions;
  final double anchor;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        // Room above and below so the first and last lines can reach the
        // anchor too.
        final height = c.maxHeight.isFinite ? c.maxHeight : 400.0;
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
          child: ScrollablePositionedList.builder(
            itemCount: lyrics.length,
            physics: const BouncingScrollPhysics(),
            itemScrollController: controller,
            itemPositionsListener: positions,
            initialScrollIndex: math.max(
              0,
              math.min(current, lyrics.length - 1),
            ),
            initialAlignment: anchor,
            padding: EdgeInsets.fromLTRB(
              24,
              height * anchor,
              24,
              height * (1 - anchor),
            ),
            itemBuilder: (context, index) {
              final isActive = index == current;
              final isPast = current >= 0 && index < current;
              final color = isActive
                  ? a.text
                  : a.textSecondary.withValues(alpha: isPast ? 0.4 : 0.65);
              return Semantics(
                button: true,
                label: lyrics[index].text,
                excludeSemantics: true,
                selected: isActive,
                onTap: () => onSeek(lyrics[index].time),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSeek(lyrics[index].time),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 6,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: color,
                        fontSize: (isActive ? 32 : 24) * scale,
                        fontWeight: isActive
                            ? FontWeight.w800
                            : FontWeight.w600,
                        height: 1.25,
                        letterSpacing: -0.4,
                      ),
                      child: Text(
                        lyrics[index].text,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Lyrics without timestamps: plain text to read, nothing to follow or tap.
class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.text, required this.scale});
  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 48),
      children: [
        Text(
          'Lyrics are not synced to the music',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: a.textSecondary),
        ),
        const SizedBox(height: 20),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22 * scale,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: a.text,
          ),
        ),
      ],
    );
  }
}
