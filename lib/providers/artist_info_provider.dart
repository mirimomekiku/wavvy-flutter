import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/utils/player.utils.dart';

class ArtistInfoState {
  final String bio;
  final String imageUrl;
  final bool isLoading;

  const ArtistInfoState({
    this.bio = "",
    this.imageUrl = "",
    this.isLoading = false,
  });

  ArtistInfoState copyWith({String? bio, String? imageUrl, bool? isLoading}) =>
      ArtistInfoState(
        bio: bio ?? this.bio,
        imageUrl: imageUrl ?? this.imageUrl,
        isLoading: isLoading ?? this.isLoading,
      );
}

final artistInfoProvider =
    NotifierProvider<ArtistInfoNotifier, ArtistInfoState>(
      ArtistInfoNotifier.new,
    );

/// Artist biography and photo from the Genius API (token from the dotenv
/// GENIUS_ACCESS_TOKEN, guarded with dotenv.isInitialized), with a
/// stale-request guard.
class ArtistInfoNotifier extends Notifier<ArtistInfoState> {
  // Monotonic id so a slow response for a previous artist can't overwrite the
  // data of the song that is playing now.
  int _requestId = 0;

  String get _geniusAccessToken =>
      dotenv.isInitialized ? (dotenv.env['GENIUS_ACCESS_TOKEN'] ?? '') : '';

  @override
  ArtistInfoState build() => const ArtistInfoState();

  Future<void> fetchArtistInfo(String artistName) async {
    final token = _geniusAccessToken;
    if (token.isEmpty || token == 'YOUR_GENIUS_ACCESS_TOKEN_HERE') {
      state = state.copyWith(
        bio: "Artist information is unavailable right now.",
      );
      return;
    }

    final int requestId = ++_requestId;
    bool isStale() => requestId != _requestId;

    try {
      state = const ArtistInfoState(isLoading: true);

      final searchUrl = Uri.parse(
        'https://api.genius.com/search?q=${Uri.encodeComponent(artistName)}',
      );
      final searchResponse = await http.get(
        searchUrl,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (isStale()) return;

      if (searchResponse.statusCode == 200) {
        final searchData = jsonDecode(searchResponse.body);
        final hits = searchData['response']['hits'] as List;

        if (hits.isNotEmpty) {
          final artistId = hits[0]['result']['primary_artist']['id'];
          final artistUrl = Uri.parse(
            'https://api.genius.com/artists/$artistId',
          );

          final artistResponse = await http.get(
            artistUrl,
            headers: {'Authorization': 'Bearer $token'},
          );

          if (isStale()) return;

          if (artistResponse.statusCode == 200) {
            final artistData = jsonDecode(artistResponse.body);
            final artist = artistData['response']['artist'];
            final description = artist['description'];

            // Extract plain text or fallback to DOM parsing
            String bio = description['plain'] ?? "";
            if (bio.trim().isEmpty && description['dom'] != null) {
              bio = PlayerUtils.extractTextFromDom(description['dom']);
            }

            state = state.copyWith(
              bio: bio.trim().isNotEmpty ? bio : "No bio available.",
              imageUrl: artist['image_url'] ?? "",
            );
          }
        } else {
          state = state.copyWith(bio: "Artist not found on Genius.");
        }
      }
    } catch (e) {
      if (isStale()) return;
      state = state.copyWith(
        bio: "Could not load this artist. Check your connection and try again.",
      );
    } finally {
      if (!isStale()) state = state.copyWith(isLoading: false);
    }
  }

  /// A `<unknown>` artist or null song clears the state; otherwise fetches.
  void refreshForSong(SongModel? song) {
    if (song == null || song.artist == "<unknown>") {
      _requestId++;
      state = const ArtistInfoState();
      return;
    }

    final artist = song.artist;
    if (artist != null) fetchArtistInfo(artist);
  }
}
