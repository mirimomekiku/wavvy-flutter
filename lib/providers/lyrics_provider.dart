import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/utils/player.utils.dart';

class LyricsState {
  final List<Lyric> lyrics;
  final int currentIndex; // -1 = none
  final bool isLoading;
  final String error;

  const LyricsState({
    this.lyrics = const [],
    this.currentIndex = -1,
    this.isLoading = false,
    this.error = "",
  });

  LyricsState copyWith({
    List<Lyric>? lyrics,
    int? currentIndex,
    bool? isLoading,
    String? error,
  }) => LyricsState(
    lyrics: lyrics ?? this.lyrics,
    currentIndex: currentIndex ?? this.currentIndex,
    isLoading: isLoading ?? this.isLoading,
    error: error ?? this.error,
  );
}

final lyricsProvider = NotifierProvider<LyricsNotifier, LyricsState>(
  LyricsNotifier.new,
);

/// UI scroll controllers for the lyrics list. Created once per app.
final lyricsScrollControllerProvider = Provider<ItemScrollController>(
  (ref) => ItemScrollController(),
);
final lyricsPositionsListenerProvider = Provider<ItemPositionsListener>(
  (ref) => ItemPositionsListener.create(),
);

/// Fetches lyrics from LRCLib (parsed by PlayerUtils.parseLrc) and tracks the
/// active line, with a stale-request guard (monotonic request id).
class LyricsNotifier extends Notifier<LyricsState> {
  // Monotonic id so a slow response for a previous song can't overwrite the
  // lyrics of the song that is playing now.
  int _requestId = 0;

  @override
  LyricsState build() => const LyricsState();

  /// GET https://lrclib.net/api/get with track/artist/album/duration.
  Future<void> fetchLyrics({
    required String trackName,
    required String artistName,
    required String albumName,
    required int duration,
  }) async {
    final int requestId = ++_requestId;
    bool isStale() => requestId != _requestId;

    try {
      state = const LyricsState(isLoading: true);

      final queryParameters = {
        'track_name': trackName,
        'artist_name': artistName,
        'album_name': albumName,
        'duration': duration.toString(),
      };

      final uri = Uri.https('lrclib.net', '/api/get', queryParameters);
      final response = await http.get(uri);
      if (isStale()) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String? syncedLyrics = data['syncedLyrics'];
        final String? plainLyrics = data['plainLyrics'];

        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          state = state.copyWith(lyrics: PlayerUtils.parseLrc(syncedLyrics));
        } else if (plainLyrics != null && plainLyrics.isNotEmpty) {
          state = state.copyWith(lyrics: [Lyric(Duration.zero, plainLyrics)]);
        } else {
          state = state.copyWith(error: "No lyrics found.");
        }
      } else if (response.statusCode == 404) {
        state = state.copyWith(error: "Lyrics not found.");
      } else {
        state = state.copyWith(error: "Error: ${response.statusCode}");
      }
    } catch (e) {
      if (isStale()) return;
      state = state.copyWith(error: "Network error.", lyrics: const []);
    } finally {
      if (!isStale()) state = state.copyWith(isLoading: false);
    }
  }

  /// Updates currentIndex for [position] (forward scan from the current index
  /// with the backwards-seek fallback). No-op if unchanged / no lyrics.
  void syncPosition(Duration position) {
    final lyrics = state.lyrics;
    if (lyrics.isEmpty) return;

    int newIndex = -1;
    final int startIndex = state.currentIndex < 0 ? 0 : state.currentIndex;

    for (int i = startIndex; i < lyrics.length; i++) {
      if (lyrics[i].time <= position) {
        newIndex = i;
      } else {
        break;
      }
    }

    // If seeking backwards, fallback to full search
    if (newIndex == -1 ||
        (newIndex == startIndex && lyrics[startIndex].time > position)) {
      for (int i = 0; i < lyrics.length; i++) {
        if (lyrics[i].time <= position) {
          newIndex = i;
        } else {
          break;
        }
      }
    }

    if (newIndex != state.currentIndex) {
      state = state.copyWith(currentIndex: newIndex);
    }
  }

  /// Clears lyrics and invalidates any in-flight request.
  void clear() {
    _requestId++;
    state = const LyricsState();
  }
}
