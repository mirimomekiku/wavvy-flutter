import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/selection_provider.dart';

SongModel _song(int id) => SongModel({
  '_id': id,
  '_data': '/music/$id.mp3',
  '_uri': 'content://media/$id',
  'title': 'Track $id',
  'duration': 180000,
});

void main() {
  final songs = [for (var i = 1; i <= 5; i++) _song(i)];
  late ProviderContainer c;
  SelectionNotifier notifier() => c.read(selectionProvider.notifier);
  SongSelection state() => c.read(selectionProvider);

  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  test('nothing is selected at first', () {
    expect(state().active, isFalse);
    expect(state().count, 0);
  });

  test('a long press starts selecting with that song', () {
    notifier().start(songs[2], scope: songs);
    expect(state().active, isTrue);
    expect(state().selected.map((s) => s.id), [3]);
    expect(state().scope, songs);
  });

  test('toggling adds in order, and removes again', () {
    notifier().start(songs[3], scope: songs);
    notifier().toggle(songs[0]);
    notifier().toggle(songs[4]);
    expect(state().selected.map((s) => s.id), [4, 1, 5]);
    notifier().toggle(songs[0]);
    expect(state().selected.map((s) => s.id), [4, 5]);
    expect(state().contains(4), isTrue);
    expect(state().contains(1), isFalse);
  });

  test('dropping the last song ends selecting', () {
    notifier().start(songs[0], scope: songs);
    notifier().toggle(songs[0]);
    expect(state().active, isFalse);
    expect(state().scope, isEmpty);
  });

  test('select all keeps what was picked first, then the rest in order', () {
    notifier().start(songs[3], scope: songs);
    notifier().selectAll();
    expect(state().selected.map((s) => s.id), [4, 1, 2, 3, 5]);
    expect(state().allSelected, isTrue);
  });

  test('select all does nothing when not selecting', () {
    notifier().selectAll();
    expect(state().active, isFalse);
  });

  test('clear ends selecting', () {
    notifier().start(songs[0], scope: songs);
    notifier().clear();
    expect(state().active, isFalse);
    notifier().clear(); // harmless when already clear
  });

  test(
    'removing deleted songs keeps the rest, and ends when none are left',
    () {
      notifier().start(songs[0], scope: songs);
      notifier().toggle(songs[1]);
      notifier().toggle(songs[2]);
      notifier().remove({1, 3});
      expect(state().selected.map((s) => s.id), [2]);
      notifier().remove({2});
      expect(state().active, isFalse);
    },
  );
}
