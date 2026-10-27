import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What is needed to reopen the player where it was left: the queue (as song
/// ids, which survive restarts), the current song, and how far into it.
class PlaybackSnapshot {
  final List<int> songIds;
  final int index;
  final int positionMs;
  final bool shuffle;

  /// `LoopMode.index`: 0 off, 1 one, 2 all.
  final int loopMode;

  const PlaybackSnapshot({
    required this.songIds,
    required this.index,
    required this.positionMs,
    this.shuffle = false,
    this.loopMode = 0,
  });

  /// The id of the song that was playing, if the index is valid.
  int? get currentId =>
      index >= 0 && index < songIds.length ? songIds[index] : null;
}

/// Where the last session is kept. Overridden in tests.
abstract class SessionStore {
  Future<PlaybackSnapshot?> load();

  /// Saves the queue. Called only when the queue changes.
  Future<void> saveQueue(List<int> ids);

  /// Saves where playback is. Called often, so kept small.
  Future<void> saveProgress({
    required int index,
    required int positionMs,
    required bool shuffle,
    required int loopMode,
  });

  Future<void> clear();
}

class PrefsSessionStore implements SessionStore {
  static const _kQueue = 'session_queue';
  static const _kProgress = 'session_progress';
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<PlaybackSnapshot?> load() async {
    try {
      final queue = await _prefs.getString(_kQueue);
      final progress = await _prefs.getString(_kProgress);
      if (queue == null || queue.isEmpty) return null;
      final ids = [
        for (final v in jsonDecode(queue) as List)
          if (v is int) v,
      ];
      if (ids.isEmpty) return null;
      final p = progress == null
          ? const <String, dynamic>{}
          : jsonDecode(progress) as Map<String, dynamic>;
      return PlaybackSnapshot(
        songIds: ids,
        index: (p['index'] as num?)?.toInt() ?? 0,
        positionMs: (p['position'] as num?)?.toInt() ?? 0,
        shuffle: p['shuffle'] == true,
        loopMode: (p['loop'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      // A damaged save is not worth failing the app start for.
      return null;
    }
  }

  @override
  Future<void> saveQueue(List<int> ids) =>
      _prefs.setString(_kQueue, jsonEncode(ids));

  @override
  Future<void> saveProgress({
    required int index,
    required int positionMs,
    required bool shuffle,
    required int loopMode,
  }) => _prefs.setString(
    _kProgress,
    jsonEncode({
      'index': index,
      'position': positionMs,
      'shuffle': shuffle,
      'loop': loopMode,
    }),
  );

  @override
  Future<void> clear() async {
    await _prefs.remove(_kQueue);
    await _prefs.remove(_kProgress);
  }
}

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => PrefsSessionStore(),
);
