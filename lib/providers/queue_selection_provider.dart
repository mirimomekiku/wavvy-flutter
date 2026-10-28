import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/player_provider.dart';

/// Rows of the play queue picked for a bulk action. Rows are told apart by
/// queue index, not song id, because a song can be queued twice.
class QueueSelection {
  const QueueSelection({this.active = false, this.picked = const {}});

  /// Selecting is on. It stays on with nothing picked until it is cancelled.
  final bool active;
  final Set<int> picked;

  int get count => picked.length;
  bool contains(int index) => picked.contains(index);

  /// The picked indices, ascending.
  List<int> get sorted => picked.toList()..sort();
}

/// Disposed with the Queue page, so leaving the page (or closing the player
/// sheet) ends selecting.
final queueSelectionProvider =
    NotifierProvider.autoDispose<QueueSelectionNotifier, QueueSelection>(
      QueueSelectionNotifier.new,
    );

class QueueSelectionNotifier extends AutoDisposeNotifier<QueueSelection> {
  @override
  QueueSelection build() {
    // Another edit can leave the picked indices pointing at other rows.
    ref.listen(playerProvider.select((s) => s.queue), (prev, next) {
      if (!state.active || prev == null) return;
      if (!_onlyAppended(prev, next)) state = const QueueSelection();
    });
    return const QueueSelection();
  }

  /// Adding to the end keeps every index valid; anything else (a removal, a
  /// move, a new queue) does not, and ends selecting.
  static bool _onlyAppended(List<SongModel> prev, List<SongModel> next) {
    if (next.length < prev.length) return false;
    for (var i = 0; i < prev.length; i++) {
      if (prev[i].id != next[i].id) return false;
    }
    return true;
  }

  List<SongModel> get _queue => ref.read(playerProvider).queue;

  /// Starts selecting with row [index] picked.
  void start(int index) {
    if (index < 0 || index >= _queue.length) return;
    state = QueueSelection(active: true, picked: {index});
  }

  /// Picks the row, or drops it if it was picked.
  void toggle(int index) {
    if (!state.active || index < 0 || index >= _queue.length) return;
    final next = {...state.picked};
    if (!next.remove(index)) next.add(index);
    state = QueueSelection(active: true, picked: next);
  }

  void selectAll() {
    if (!state.active) return;
    state = QueueSelection(
      active: true,
      picked: {for (var i = 0; i < _queue.length; i++) i},
    );
  }

  void selectNone() {
    if (state.active) state = const QueueSelection(active: true);
  }

  void clear() {
    if (state.active) state = const QueueSelection();
  }
}
