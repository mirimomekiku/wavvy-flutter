import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/db/db.dart';
import 'package:wavvy/providers/library_provider.dart';

/// Where favorites are kept. Overridden in tests.
abstract class FavoritesStore {
  Future<Map<int, int>> load();
  Future<void> add(int songId, int addedAt);
  Future<void> remove(int songId);
}

class DbFavoritesStore implements FavoritesStore {
  final DbHelper _db = DbHelper();

  @override
  Future<Map<int, int>> load() => _db.favoriteRows();

  @override
  Future<void> add(int songId, int addedAt) => _db.addFavorite(songId, addedAt);

  @override
  Future<void> remove(int songId) => _db.removeFavorite(songId);
}

final favoritesStoreProvider = Provider<FavoritesStore>(
  (ref) => DbFavoritesStore(),
);

/// song id -> when it was favorited (milliseconds since the epoch).
final favoritesProvider = NotifierProvider<FavoritesNotifier, Map<int, int>>(
  FavoritesNotifier.new,
);

class FavoritesNotifier extends Notifier<Map<int, int>> {
  @override
  Map<int, int> build() {
    Future.microtask(() async {
      try {
        final saved = await ref.read(favoritesStoreProvider).load();
        // Anything toggled while this was loading wins.
        state = {...saved, ...state};
      } catch (e) {
        // No favorites is better than no app.
        debugPrint('could not load favorites: $e');
      }
    });
    return const {};
  }

  bool isFavorite(int songId) => state.containsKey(songId);

  Future<void> toggle(SongModel song) async {
    final store = ref.read(favoritesStoreProvider);
    if (state.containsKey(song.id)) {
      state = {...state}..remove(song.id);
      await store.remove(song.id);
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      state = {song.id: now, ...state};
      await store.add(song.id, now);
    }
  }
}

/// The favorites that are still in the library, newest first.
final likedSongsProvider = Provider<List<SongModel>>((ref) {
  final favorites = ref.watch(favoritesProvider);
  final songs = ref.watch(libraryProvider.select((s) => s.songs));
  final byId = {for (final s in songs) s.id: s};
  final ids = favorites.keys.where(byId.containsKey).toList()
    ..sort((a, b) => favorites[b]!.compareTo(favorites[a]!));
  return [for (final id in ids) byId[id]!];
});
