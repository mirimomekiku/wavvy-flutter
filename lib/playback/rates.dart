import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Speed and pitch.
class PlaybackRate {
  final double speed;
  final double pitch;

  const PlaybackRate(this.speed, this.pitch);
  static const normal = PlaybackRate(1, 1);

  bool get isNormal => (speed - 1).abs() < 0.001 && (pitch - 1).abs() < 0.001;
}

/// The group a song's speed is remembered for: its album, or when it has none
/// its folder.
String rateKey(SongModel song) {
  final album = song.albumId;
  if (album != null) return 'a:$album';
  final path = song.data;
  final slash = path.lastIndexOf('/');
  return 'd:${slash <= 0 ? path : path.substring(0, slash)}';
}

abstract class RateStore {
  Future<Map<String, PlaybackRate>> load();
  Future<void> save(Map<String, PlaybackRate> rates);
}

class PrefsRateStore implements RateStore {
  static const _key = 'playback_rates';
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<Map<String, PlaybackRate>> load() async {
    try {
      final raw = await _prefs.getString(_key);
      if (raw == null) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          if (e.value is List && (e.value as List).length == 2)
            e.key: PlaybackRate(
              ((e.value as List)[0] as num).toDouble(),
              ((e.value as List)[1] as num).toDouble(),
            ),
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, PlaybackRate> rates) => _prefs.setString(
    _key,
    jsonEncode({
      for (final e in rates.entries) e.key: [e.value.speed, e.value.pitch],
    }),
  );
}

final rateStoreProvider = Provider<RateStore>((ref) => PrefsRateStore());

/// Speed and pitch remembered per album or folder: an audiobook can play at 1.4x
/// while music stays at 1x.
final playbackRatesProvider =
    NotifierProvider<PlaybackRatesNotifier, Map<String, PlaybackRate>>(
      PlaybackRatesNotifier.new,
    );

class PlaybackRatesNotifier extends Notifier<Map<String, PlaybackRate>> {
  final Completer<void> _ready = Completer<void>();

  /// Completes once the saved rates have been read.
  Future<void> get ready => _ready.future;

  @override
  Map<String, PlaybackRate> build() {
    Future.microtask(() async {
      try {
        final saved = await ref.read(rateStoreProvider).load();
        state = {...saved, ...state};
      } finally {
        if (!_ready.isCompleted) _ready.complete();
      }
    });
    return const {};
  }

  /// The rate to use for [song]: what was remembered, or normal speed.
  PlaybackRate rateFor(SongModel song) =>
      state[rateKey(song)] ?? PlaybackRate.normal;

  /// Remembers [rate] for [song]'s album or folder. Normal speed is not stored.
  Future<void> remember(SongModel song, PlaybackRate rate) async {
    final next = {...state};
    if (rate.isNormal) {
      next.remove(rateKey(song));
    } else {
      next[rateKey(song)] = rate;
    }
    state = next;
    await ref.read(rateStoreProvider).save(next);
  }
}
