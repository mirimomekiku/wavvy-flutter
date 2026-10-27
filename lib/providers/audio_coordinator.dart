import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wavvy/providers/artist_info_provider.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

/// Wires the cross-provider side effects that AudioController.onInit (and
/// ShakeController, and the audio handler's session listener) used to set up
/// with GetX workers. Watch it ONCE from the app root:
///
///     ref.watch(audioCoordinatorProvider);
///
/// Implement with ref.listen + Timers; cancel everything in ref.onDispose.
/// Behaviors to port:
///  1. Song change (debounced 300ms; playerProvider.currentSong):
///       song != null -> paletteProvider.updateForSong(id); if
///       settings.enableArtistInfoFetching -> artistInfo.refreshForSong(song);
///       if settings.enableLyricsFetching -> lyrics.fetchLyrics(...)
///       (duration in seconds = song.duration ~/ 1000)
///       song == null -> palette.clear(); lyrics.clear().
///  2. settings.enableDynamicColors changes -> re-run palette update for the
///     current song (or palette.clear() when disabled -> updateForSong
///     handles the disabled branch).
///  3. Position ticks (positionProvider), throttled to 1s for play logging
///     and 200ms for lyrics:
///       - Play logging (skip when settings.isIncognitoMode): if
///         position < 2s and lastLoggedSongId == current id -> reset it; threshold =
///         durationSec > 0 ? (durationSec ~/ 2).clamp(3, 15) : 15; when
///         position >= threshold and lastLoggedSongId != id ->
///         playlists.logSongPlay(id), remember id.
///       - Lyrics: if lyrics non-empty -> lyrics.syncPosition(position).
///  4. Lyrics auto-scroll: when lyricsProvider.currentIndex changes to >= 0,
///     not loading, and lyricsScrollController.isAttached ->
///     scrollTo(index, 400ms, Curves.easeInOutCubic, alignment 0.5).
///  5. Shake to skip: while settings.enableShakeToSkip, listen to
///     accelerometerEventStream (sensors_plus); magnitude > 25 and > 2000ms
///     since last shake and player has a next track -> playerNotifier.next().
///     Start/stop when the setting toggles.
///  6. Audio session id: audioPlayer.androidAudioSessionIdStream -> on a
///     non-null id call nativeEffectsChannel.initEffects(id) and
///     effectsProvider.notifier.resetState().
///  7. First frame: libraryProvider.notifier.fetchAllSongs().
final audioCoordinatorProvider = Provider<void>((ref) {
  // ------------------------------------------------ 1. Song change (debounce)
  Timer? songDebounce;
  ref.listen(playerProvider.select((s) => s.currentSong), (prev, song) {
    songDebounce?.cancel();
    songDebounce = Timer(const Duration(milliseconds: 300), () {
      if (song != null) {
        ref.read(paletteProvider.notifier).updateForSong(song.id);

        final settings = ref.read(settingsProvider);
        if (settings.enableArtistInfoFetching) {
          ref.read(artistInfoProvider.notifier).refreshForSong(song);
        }

        if (settings.enableLyricsFetching) {
          final int durationSeconds = (song.duration ?? 0) ~/ 1000;
          ref
              .read(lyricsProvider.notifier)
              .fetchLyrics(
                trackName: song.title,
                artistName: song.artist ?? "",
                albumName: song.album ?? "",
                duration: durationSeconds,
              );
        }
      } else {
        ref.read(paletteProvider.notifier).clear();
        ref.read(lyricsProvider.notifier).clear();
      }
    });
  });
  ref.onDispose(() => songDebounce?.cancel());

  // ------------------------------------------- 2. Dynamic colors toggled
  ref.listen(settingsProvider.select((s) => s.enableDynamicColors), (_, _) {
    final song = ref.read(playerProvider).currentSong;
    if (song != null) {
      ref.read(paletteProvider.notifier).updateForSong(song.id);
    }
  });

  // ---------------------------------------------------- 3. Position ticks
  int? lastLoggedSongId;
  int lastLogTickMs = 0;
  int lastLyricsTickMs = 0;
  ref.listen(positionProvider, (prev, position) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Play logging (1s throttle). Incognito is checked on every tick.
    if (now - lastLogTickMs >= 1000) {
      lastLogTickMs = now;
      final song = ref.read(playerProvider).currentSong;
      if (song != null && !ref.read(settingsProvider).isIncognitoMode) {
        // Restarting the same song (repeat-one, seek to start) counts again.
        if (position.inSeconds < 2 && lastLoggedSongId == song.id) {
          lastLoggedSongId = null;
        }

        final int durationSec = (song.duration ?? 0) ~/ 1000;
        final int threshold = durationSec > 0
            ? (durationSec ~/ 2).clamp(3, 15)
            : 15;

        if (position.inSeconds >= threshold && lastLoggedSongId != song.id) {
          lastLoggedSongId = song.id;
          ref.read(playlistsProvider.notifier).logSongPlay(song.id);
        }
      }
    }

    // Lyrics sync (200ms throttle).
    if (now - lastLyricsTickMs >= 200) {
      lastLyricsTickMs = now;
      if (ref.read(lyricsProvider).lyrics.isNotEmpty) {
        ref.read(lyricsProvider.notifier).syncPosition(position);
      }
    }
  });

  // ------------------------------------------------ 4. Lyrics auto-scroll
  ref.listen(lyricsProvider.select((s) => s.currentIndex), (prev, index) {
    final controller = ref.read(lyricsScrollControllerProvider);
    if (index >= 0 &&
        !ref.read(lyricsProvider).isLoading &&
        controller.isAttached) {
      controller.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.5,
      );
    }
  });

  // ---------------------------------------------------- 5. Shake to skip
  const double shakeThreshold = 25.0;
  const int shakeDebounceMs = 2000;
  StreamSubscription<AccelerometerEvent>? shakeSub;
  int lastShakeTime = 0;

  void stopShake() {
    shakeSub?.cancel();
    shakeSub = null;
  }

  void startShake() {
    if (shakeSub != null) return;
    shakeSub = accelerometerEventStream().listen((event) {
      final double acceleration = sqrt(
        pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2),
      );
      if (acceleration > shakeThreshold) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastShakeTime > shakeDebounceMs) {
          lastShakeTime = now;
          if (ref.read(audioPlayerProvider).hasNext) {
            ref.read(playerProvider.notifier).next();
          }
        }
      }
    });
  }

  if (ref.read(settingsProvider).enableShakeToSkip) startShake();
  ref.listen(settingsProvider.select((s) => s.enableShakeToSkip), (_, enabled) {
    if (enabled) {
      startShake();
    } else {
      stopShake();
    }
  });
  ref.onDispose(stopShake);

  // -------------------------------------------------- 6. Audio session id
  final sessionSub = ref
      .read(audioPlayerProvider)
      .androidAudioSessionIdStream
      .listen((sessionId) async {
        if (sessionId == null) return;
        try {
          await ref.read(nativeEffectsChannelProvider).initEffects(sessionId);
        } catch (_) {}
        ref.read(effectsProvider.notifier).resetState();
      });
  ref.onDispose(sessionSub.cancel);

  // ------------------------------------- 8. Reload the library on resume
  // New songs appear without a restart, and granting storage access in the
  // system settings recovers a denied library. Silent: never re-prompts.
  var lastResumeFetch = DateTime.fromMillisecondsSinceEpoch(0);
  final lifecycle = AppLifecycleListener(
    onResume: () {
      final denied = ref.read(libraryProvider).permissionDenied;
      final now = DateTime.now();
      if (!denied &&
          now.difference(lastResumeFetch) < const Duration(seconds: 10)) {
        return;
      }
      lastResumeFetch = now;
      ref.read(libraryProvider.notifier).fetchAllSongs(silent: true);
    },
  );
  ref.onDispose(lifecycle.dispose);

  // ------------------------------------------------------ 7. First frame
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(libraryProvider.notifier).fetchAllSongs();
  });
});
