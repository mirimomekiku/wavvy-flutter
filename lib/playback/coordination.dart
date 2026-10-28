// AudioDeviceType is marked experimental in audio_session; it is the only way
// to tell headphones from the speaker, and a change would show up here.
// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:audio_session/audio_session.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/home_widget.dart';
import 'package:wavvy/playback/ab_loop.dart';
import 'package:wavvy/playback/focus.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/playback/replay_gain.dart';
import 'package:wavvy/playback/session.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

/// Connects the playback features to the player. Called once, from the app's
/// coordinator; everything it starts is cancelled when [ref] is disposed.
///
///  1. Last session: save the queue and position, and reopen them (paused).
///  2. Focus: calls, notifications and headphones, by the user's settings.
///  3. ReplayGain: level each track from its tags.
///  4. Crossfade length, from settings.
///  5. A-B loop: jump back from B to A.
///  6. Remembered speed and pitch per album.
///  7. Sleep timer "end of track / queue".
///  8. Home-screen widget: what is playing.
void wirePlayback(Ref ref) {
  _wireSession(ref);
  _wireFocus(ref);
  _wireReplayGain(ref);
  _wireCrossfade(ref);
  _wirePositionRules(ref);
  _wireRates(ref);
  _wireWidget(ref);
}

// ------------------------------------------------------------ 1. Session

void _wireSession(Ref ref) {
  final store = ref.read(sessionStoreProvider);
  final player = ref.read(playerProvider.notifier);
  var restored = false;
  var savedQueue = <int>[];
  var restoreFailed = false;
  Timer? debounce;

  Future<void> saveProgress() async {
    if (!ref.read(settingsProvider).resumeSession) return;
    final snap = player.snapshot(ref.read(positionProvider));
    if (snap == null) return;
    await store.saveProgress(
      index: snap.index,
      positionMs: snap.positionMs,
      shuffle: snap.shuffle,
      loopMode: snap.loopMode,
    );
  }

  Future<void> saveQueue() async {
    if (!ref.read(settingsProvider).resumeSession) return;
    final queue = ref.read(playerProvider).queue;
    if (queue.isEmpty) {
      // The user emptied the queue; do not bring it back next time. A restore
      // that failed leaves the queue empty too, and must not erase the stored
      // session.
      if (restored && !restoreFailed) await store.clear();
      savedQueue = const [];
      return;
    }
    restoreFailed = false;
    final ids = [for (final s in queue) s.id];
    if (!listEquals(ids, savedQueue)) {
      savedQueue = ids;
      await store.saveQueue(ids);
    }
    await saveProgress();
  }

  ref.listen(playerProvider.select((s) => s.queue), (_, _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 600), saveQueue);
  });
  ref.listen(playerProvider.select((s) => s.currentIndex), (_, _) {
    unawaited(saveProgress());
  });
  ref.listen(playerProvider.select((s) => s.isPlaying), (_, _) {
    unawaited(saveProgress());
  });
  ref.listen(playerProvider.select((s) => s.isShuffleModeEnabled), (_, _) {
    unawaited(saveProgress());
  });
  ref.listen(playerProvider.select((s) => s.loopMode), (_, _) {
    unawaited(saveProgress());
  });
  final ticker = Timer.periodic(const Duration(seconds: 5), (_) {
    if (ref.read(playerProvider).isPlaying) unawaited(saveProgress());
  });
  final lifecycle = AppLifecycleListener(
    onInactive: () => unawaited(saveProgress()),
    onHide: () => unawaited(saveProgress()),
    onPause: () => unawaited(saveProgress()),
  );
  ref.onDispose(() {
    debounce?.cancel();
    ticker.cancel();
    lifecycle.dispose();
  });

  // Reopen the last session once the library is known: the saved queue is song
  // ids, which only mean something against the library.
  Future<void> tryRestore() async {
    if (restored) return;
    final songs = ref.read(libraryProvider).songs;
    if (songs.isEmpty) return;
    restored = true;
    if (!ref.read(settingsProvider).resumeSession) return;
    // Something is already playing: leave it alone.
    if (ref.read(playerProvider).queue.isNotEmpty) return;
    final saved = await store.load();
    if (saved == null) return;
    // The user may have started something while the session was loading.
    if (ref.read(playerProvider).queue.isNotEmpty) return;
    final ok = await player.restoreSession(saved, songs);
    if (ok) {
      savedQueue = [for (final s in ref.read(playerProvider).queue) s.id];
    } else {
      restoreFailed = true;
    }
  }

  ref.listen(libraryProvider.select((s) => s.songs), (_, _) => tryRestore());
  unawaited(tryRestore());
}

// -------------------------------------------------------------- 2. Focus

FocusInterruption _interruption(AudioInterruptionType type) => switch (type) {
  AudioInterruptionType.duck => FocusInterruption.duck,
  AudioInterruptionType.pause => FocusInterruption.pause,
  AudioInterruptionType.unknown => FocusInterruption.unknown,
};

bool _isHeadphones(AudioDevice d) =>
    d.isOutput &&
    switch (d.type) {
      AudioDeviceType.wiredHeadset ||
      AudioDeviceType.wiredHeadphones ||
      AudioDeviceType.bluetoothA2dp ||
      AudioDeviceType.bluetoothLe ||
      AudioDeviceType.usbAudio => true,
      _ => false,
    };

void _wireFocus(Ref ref) {
  final handler = ref.read(audioHandlerProvider);
  final subs = <StreamSubscription<dynamic>>[];
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    for (final s in subs) {
      s.cancel();
    }
  });

  () async {
    try {
      final session = await AudioSession.instance;
      if (disposed) return;
      final controller = FocusController(
        target: handler.focusTarget,
        policy: () {
          final s = ref.read(settingsProvider);
          return FocusPolicy(
            pauseOnUnplug: s.pauseOnUnplug,
            duck: s.duckOnInterruption,
            resumeAfterInterruption: s.resumeAfterInterruption,
            resumeOnReconnect: s.resumeOnReconnect,
          );
        },
      );
      handler.focus = controller;
      subs
        ..add(
          session.interruptionEventStream.listen(
            (e) => controller.onInterruption(e.begin, _interruption(e.type)),
          ),
        )
        ..add(
          session.becomingNoisyEventStream.listen(
            (_) => controller.onBecomingNoisy(),
          ),
        )
        ..add(
          session.devicesChangedEventStream.listen((e) {
            if (e.devicesAdded.any(_isHeadphones)) {
              controller.onHeadphonesConnected();
            }
          }),
        );
    } catch (e) {
      debugPrint('audio focus handling unavailable: $e');
    }
  }();
}

// ---------------------------------------------------------- 3. ReplayGain

void _wireReplayGain(Ref ref) {
  final handler = ref.read(audioHandlerProvider);
  final cache = ref.read(replayGainCacheProvider);
  var generation = 0;

  Future<void> apply() async {
    final mode = ReplayGainMode.fromIndex(
      ref.read(settingsProvider).replayGainMode,
    );
    final state = ref.read(playerProvider);
    final song = state.currentSong;
    final mine = ++generation;
    var db = 0.0;
    if (song != null && mode != ReplayGainMode.off) {
      db = replayGainDb(await cache.tagsFor(song), mode);
    }
    // The track changed while the file was being read.
    if (mine != generation) return;
    await handler.setReplayGain(db);
    // Read the next track's tags ahead, so its level is ready at once.
    if (song != null && mode != ReplayGainMode.off) {
      final next = state.currentIndex + 1;
      if (next >= 0 && next < state.queue.length) {
        unawaited(cache.tagsFor(state.queue[next]));
      }
    }
  }

  ref.listen(playerProvider.select((s) => s.currentSong?.id), (_, _) {
    unawaited(apply());
  });
  ref.listen(settingsProvider.select((s) => s.replayGainMode), (_, _) {
    unawaited(apply());
  });
}

// ---------------------------------------------------------- 4. Crossfade

void _wireCrossfade(Ref ref) {
  final handler = ref.read(audioHandlerProvider);
  void apply() => handler.crossfader.fade = Duration(
    seconds: ref.read(settingsProvider).crossfadeSeconds,
  );
  apply();
  ref.listen(settingsProvider.select((s) => s.crossfadeSeconds), (_, _) {
    apply();
    // Turning it off mid-fade must not leave the volume down.
    if (ref.read(settingsProvider).crossfadeSeconds == 0) {
      handler.crossfader.cancel();
    }
  });
}

// ----------------------------------------------- 5 and 7. Position rules

void _wirePositionRules(Ref ref) {
  final player = ref.read(playerProvider.notifier);
  ref.listen(positionProvider, (_, position) {
    // A-B loop: past B, go back to A.
    final jump = ref.read(abLoopProvider.notifier).jumpFor(position);
    if (jump != null) unawaited(player.seek(jump));

    // Sleep timer "end of track / queue".
    player.onPosition(
      position,
      ref.read(durationProvider),
      lead: Duration(seconds: ref.read(settingsProvider).crossfadeSeconds),
    );
  });
  // A loop belongs to one song.
  ref.listen(playerProvider.select((s) => s.currentSong?.id), (_, _) {
    ref.read(abLoopProvider.notifier).clear();
  });
}

// ---------------------------------------------------------------- 6. Rates

void _wireRates(Ref ref) {
  Future<void> apply(SongModel song) async {
    if (!ref.read(settingsProvider).rememberRates) return;
    final rates = ref.read(playbackRatesProvider.notifier);
    await rates.ready;
    // The song changed while the saved rates were loading.
    if (ref.read(playerProvider).currentSong?.id != song.id) return;
    final rate = rates.rateFor(song);
    final audio = ref.read(audioPlayerProvider);
    if ((audio.speed - rate.speed).abs() > 0.001) {
      await audio.setSpeed(rate.speed);
    }
    if ((audio.pitch - rate.pitch).abs() > 0.001) {
      await audio.setPitch(rate.pitch);
    }
  }

  ref.listen(playerProvider.select((s) => s.currentSong), (prev, song) {
    // Only when the album or folder changes: a track change inside one album
    // keeps whatever speed is set, including a change made just now.
    if (song == null) return;
    if (prev != null && rateKey(prev) == rateKey(song)) return;
    unawaited(apply(song));
  });
}

// ------------------------------------------------------------- 8. Widget

void _wireWidget(Ref ref) {
  Timer? debounce;
  int? artFor;

  Future<void> push() async {
    final state = ref.read(playerProvider);
    final song = state.currentSong;
    Uint8List? art;
    // The picture is only sent when the song changes: it is the big part.
    if (song == null) {
      art = artFor == null ? null : Uint8List(0);
      artFor = null;
    } else if (artFor != song.id) {
      artFor = song.id;
      try {
        art =
            await ref
                .read(audioQueryProvider)
                .queryArtwork(
                  song.id,
                  ArtworkType.AUDIO,
                  format: ArtworkFormat.JPEG,
                  size: 220,
                  quality: 85,
                ) ??
            Uint8List(0);
      } catch (_) {
        art = Uint8List(0);
      }
    }
    await ref
        .read(homeWidgetProvider)
        .update(
          title: song?.title ?? 'Wavvy',
          artist: song == null ? 'Tap to open' : (song.artist ?? 'Unknown'),
          playing: state.isPlaying,
          art: art,
        );
  }

  void schedule() {
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(push()),
    );
  }

  ref.listen(
    playerProvider.select((s) => s.currentSong?.id),
    (_, _) => schedule(),
  );
  ref.listen(playerProvider.select((s) => s.isPlaying), (_, _) => schedule());
  ref.onDispose(() => debounce?.cancel());
}
