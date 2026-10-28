import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wavvy/playback/coordination.dart';
import 'package:wavvy/playback/history.dart';
import 'package:wavvy/providers/album_art_provider.dart';
import 'package:wavvy/providers/artist_info_provider.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

/// Wires the cross-provider side effects: track-change enrichment, play
/// logging, lyric sync and scrolling, shake-to-skip, audio-session effects, the
/// playback settings and library reloads. Watch it ONCE from the app root:
///
///     ref.watch(audioCoordinatorProvider);
///
/// Everything it starts is cancelled in ref.onDispose.
///  1. Song change (debounced 300ms): refresh the palette, artist info and
///     lyrics for the new song, or clear them when nothing is loaded.
///  2. Dynamic colors toggled: re-run the palette for the current song.
///  3. Position ticks: log a play once a song passes its threshold (1s throttle,
///     skipped in incognito) and sync the lyrics (200ms throttle).
///  4. Lyrics auto-scroll to the active line.
///  5. Shake to skip while the setting is on.
///  6. Audio session id: (re)create the native effects and reapply the user's
///     effect settings.
///  7. First frame: load the library.
///  8. App resume: reload the library silently.
///  9. Playback settings: fade in/out and skip silence.
/// 10. Last session, audio focus, ReplayGain, crossfade, A-B loop, remembered
///     speed and the sleep timer's end-of-track rule (lib/playback/).
final audioCoordinatorProvider = Provider<void>((ref) {
  // Missing album covers (off unless the setting is on) and the notification art.
  ref.watch(albumArtAutoProvider);

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
          // The play counter belongs to library songs (history logs all).
          if (song.id >= 0) {
            ref.read(playlistsProvider.notifier).logSongPlay(song.id);
          }
          ref.read(historyLoggerProvider).logPlay(song);
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
          final settings = ref.read(settingsProvider);
          final player = ref.read(playerProvider.notifier);
          if (settings.shakeExtendsSleep &&
              player.sleepNearEnd &&
              player.extendSleep()) {
            // The timer was about to stop the music: a shake adds time.
          } else if (settings.enableShakeToSkip &&
              ref.read(audioPlayerProvider).hasNext) {
            player.next();
          }
        }
      }
    });
  }

  bool wantsShake(SettingsState s) =>
      s.enableShakeToSkip || s.shakeExtendsSleep;
  if (wantsShake(ref.read(settingsProvider))) startShake();
  ref.listen(settingsProvider.select(wantsShake), (_, enabled) {
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
        await ref.read(effectsProvider.notifier).attachToSession(sessionId);
      });
  ref.onDispose(sessionSub.cancel);

  // -------------------- 10. Session, focus, ReplayGain, crossfade, loop, rates
  wirePlayback(ref);

  // ---------------------------------------------- 9. Playback settings
  void applyPlaybackSettings(SettingsState settings) {
    ref.read(audioHandlerProvider).fadeEnabled = settings.enableFadeInOut;
    ref
        .read(audioPlayerProvider)
        .setSkipSilenceEnabled(settings.enableSkipSilence);
  }

  applyPlaybackSettings(ref.read(settingsProvider));
  ref.listen(settingsProvider, (prev, next) {
    if (prev?.enableFadeInOut != next.enableFadeInOut ||
        prev?.enableSkipSilence != next.enableSkipSilence) {
      applyPlaybackSettings(next);
    }
  });

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
