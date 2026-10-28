import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// Songs picked for a bulk action (play, queue, playlist, favorites, share,
/// delete), in the order they were picked.
class SongSelection {
  const SongSelection({this.selected = const [], this.scope = const []});

  final List<SongModel> selected;

  /// The list the selection was started in, which "Select all" selects.
  final List<SongModel> scope;

  /// Selecting is on while at least one song is picked.
  bool get active => selected.isNotEmpty;
  int get count => selected.length;
  bool contains(int songId) => selected.any((s) => s.id == songId);
  bool get allSelected =>
      scope.isNotEmpty && scope.every((s) => contains(s.id));
}

final selectionProvider = NotifierProvider<SelectionNotifier, SongSelection>(
  SelectionNotifier.new,
);

class SelectionNotifier extends Notifier<SongSelection> {
  @override
  SongSelection build() => const SongSelection();

  /// Starts selecting with [song] picked. [scope] is the list it came from.
  void start(SongModel song, {List<SongModel> scope = const []}) {
    state = SongSelection(selected: [song], scope: scope);
  }

  /// Picks the song, or drops it if it was picked. Dropping the last one ends
  /// selecting.
  void toggle(SongModel song) {
    if (state.contains(song.id)) {
      final left = [
        for (final s in state.selected)
          if (s.id != song.id) s,
      ];
      state = left.isEmpty
          ? const SongSelection()
          : SongSelection(selected: left, scope: state.scope);
    } else {
      state = SongSelection(
        selected: [...state.selected, song],
        scope: state.scope,
      );
    }
  }

  /// Picks every song of the list selecting started in, keeping the order
  /// they were already picked in.
  void selectAll() {
    if (!state.active) return;
    final picked = {for (final s in state.selected) s.id};
    state = SongSelection(
      selected: [
        ...state.selected,
        for (final s in state.scope)
          if (picked.add(s.id)) s,
      ],
      scope: state.scope,
    );
  }

  void clear() {
    if (state.active) state = const SongSelection();
  }

  /// Forgets songs that no longer exist (after a delete); ends selecting when
  /// none are left.
  void remove(Set<int> songIds) {
    if (!state.active) return;
    final left = [
      for (final s in state.selected)
        if (!songIds.contains(s.id)) s,
    ];
    state = left.isEmpty
        ? const SongSelection()
        : SongSelection(selected: left, scope: state.scope);
  }
}

/// Ends picking when the app moves to another page, so a selection never
/// follows the user to a screen it was not made on. Dialogs and sheets (a
/// confirmation, the playlist picker) are not pages and leave it alone.
final selectionObserverProvider = Provider<NavigatorObserver>(
  (ref) => _PageObserver(() => ref.read(selectionProvider.notifier).clear()),
);

class _PageObserver extends NavigatorObserver {
  _PageObserver(this._onPage);
  final VoidCallback _onPage;

  void _check(Route<dynamic>? route) {
    // After the navigator is done, not in the middle of it.
    if (route is PageRoute) Future<void>.microtask(_onPage);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _check(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _check(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _check(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _check(newRoute);
}
