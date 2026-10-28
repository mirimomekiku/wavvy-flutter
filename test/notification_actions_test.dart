import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/instances/audio_handler.instance.dart';
import 'package:wavvy/playback/favorites.dart';
import 'package:wavvy/playback/notification_actions.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

import 'helpers/fake_player.dart';

class _Handler extends Fake implements WavvyAudioHandler {
  final pushed = <NotificationExtras>[];
  @override
  CustomActionDelegate? customActionDelegate;

  @override
  void updateCustomControls(NotificationExtras extras) => pushed.add(extras);

  NotificationExtras get last => pushed.last;
}

class _Favorites implements FavoritesStore {
  final added = <int>[];
  final removed = <int>[];
  @override
  Future<Map<int, int>> load() async => {};
  @override
  Future<void> add(int songId, int addedAt) async => added.add(songId);
  @override
  Future<void> remove(int songId) async => removed.add(songId);
}

class _Library extends LibraryNotifier {
  @override
  LibraryState build() => const LibraryState();
  @override
  Future<void> fetchAllSongs({bool silent = false}) async {}
}

final _wire = Provider<void>((ref) => wireNotificationActions(ref));

List<String> _labels(List<MediaControl> c) => [for (final x in c) x.label];

List<String> _names(bool playing, NotificationExtras e) => [
  for (final c in buildNotificationControls(playing: playing, extras: e))
    c.customAction?.name ?? c.label,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('buildNotificationControls', () {
    test('nothing extra: the four standard buttons', () {
      final c = buildNotificationControls(
        playing: true,
        extras: const NotificationExtras(),
      );
      expect(c, [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.skipToNext,
        MediaControl.stop,
      ]);
      expect(
        buildNotificationControls(
          playing: false,
          extras: const NotificationExtras(),
        )[1],
        MediaControl.play,
      );
    });

    test('every combination: order, count and the cap of five', () {
      for (var mask = 0; mask < 8; mask++) {
        final like = mask & 1 != 0;
        final shuffle = mask & 2 != 0;
        final repeat = mask & 4 != 0;
        final c = buildNotificationControls(
          playing: true,
          extras: NotificationExtras(
            likeEnabled: like,
            shuffleEnabled: shuffle,
            repeatEnabled: repeat,
            canLike: true,
          ),
        );
        final extras = [
          if (like) kLikeAction,
          if (shuffle) kShuffleAction,
          if (repeat) kRepeatAction,
        ];
        final names = [for (final x in c) x.customAction?.name];
        expect(
          names.skip(3).whereType<String>(),
          extras.take(2),
          reason: '$mask',
        );
        expect(c.length, lessThanOrEqualTo(kMaxNotificationControls));
        // Stop only when there is room: three standard + extras + stop <= 5.
        expect(
          c.contains(MediaControl.stop),
          extras.length <= 1,
          reason: '$mask',
        );
        expect(c.sublist(0, 3), [
          MediaControl.skipToPrevious,
          MediaControl.pause,
          MediaControl.skipToNext,
        ]);
      }
    });

    test('one extra keeps Stop, last', () {
      final c = buildNotificationControls(
        playing: true,
        extras: const NotificationExtras(likeEnabled: true, canLike: true),
      );
      expect(c.length, 5);
      expect(c.last, MediaControl.stop);
      expect(c[3].customAction?.name, kLikeAction);
    });

    test('like: icon and label follow the favorite state', () {
      final off = buildNotificationControls(
        playing: true,
        extras: const NotificationExtras(likeEnabled: true, canLike: true),
      )[3];
      final on = buildNotificationControls(
        playing: true,
        extras: const NotificationExtras(
          likeEnabled: true,
          canLike: true,
          liked: true,
        ),
      )[3];
      expect(off.label, 'Like');
      expect(off.androidIcon, 'drawable/ic_notif_like');
      expect(on.label, 'Unlike');
      expect(on.androidIcon, 'drawable/ic_notif_like_filled');
      expect(off.action, MediaAction.custom);
    });

    test('shuffle: off and on', () {
      MediaControl at(bool on) => buildNotificationControls(
        playing: true,
        extras: NotificationExtras(shuffleEnabled: true, shuffle: on),
      )[3];
      expect(at(false).label, 'Shuffle off');
      expect(at(false).androidIcon, 'drawable/ic_notif_shuffle');
      expect(at(true).label, 'Shuffle on');
      expect(at(true).androidIcon, 'drawable/ic_notif_shuffle_on');
    });

    test('repeat: off, all and one', () {
      MediaControl at(LoopMode m) => buildNotificationControls(
        playing: true,
        extras: NotificationExtras(repeatEnabled: true, repeat: m),
      )[3];
      expect(_labels([at(LoopMode.off), at(LoopMode.all), at(LoopMode.one)]), [
        'Repeat off',
        'Repeat all',
        'Repeat one',
      ]);
      expect(at(LoopMode.off).androidIcon, 'drawable/ic_notif_repeat');
      expect(at(LoopMode.all).androidIcon, 'drawable/ic_notif_repeat_all');
      expect(at(LoopMode.one).androidIcon, 'drawable/ic_notif_repeat_one');
    });

    test('no Like without a library song (external or nothing playing)', () {
      expect(
        _names(
          true,
          const NotificationExtras(likeEnabled: true, canLike: false),
        ),
        ['Previous', 'Pause', 'Next', 'Stop'],
      );
    });

    test('the compact notification is still Previous, Play/Pause, Next', () {
      expect(kCompactActionIndices, [0, 1, 2]);
    });
  });

  group('wireNotificationActions', () {
    late MemoryPlayer player;
    late _Handler handler;
    late _Favorites store;
    late ProviderContainer container;
    final lib = testSong(1, albumId: 100);
    final other = testSong(2, albumId: 100);
    final external = testSong(-7, albumId: 100);

    void build({SettingsState settings = const SettingsState()}) {
      player = MemoryPlayer();
      handler = _Handler();
      store = _Favorites();
      container = ProviderContainer(
        overrides: [
          audioPlayerProvider.overrideWithValue(player),
          audioHandlerProvider.overrideWithValue(handler),
          favoritesStoreProvider.overrideWithValue(store),
          libraryProvider.overrideWith(_Library.new),
          settingsProvider.overrideWith(() => _Settings(settings)),
          playCountsLoaderProvider.overrideWithValue(() async => {}),
        ],
      );
      addTearDown(container.dispose);
      container.read(_wire);
    }

    Future<void> pump() =>
        Future<void>.delayed(const Duration(milliseconds: 20));

    PlayerNotifier notifier() => container.read(playerProvider.notifier);

    test('pushes the starting state: Like on, nothing playing', () {
      build();
      expect(handler.last.likeEnabled, isTrue);
      expect(handler.last.shuffleEnabled, isFalse);
      expect(handler.last.repeatEnabled, isFalse);
      expect(handler.last.canLike, isFalse);
    });

    test('like toggles the favorite and pushes the new state', () async {
      build();
      await notifier().playSong(lib, contextList: [lib, other]);
      await pump();
      expect(handler.last.canLike, isTrue);
      expect(handler.last.liked, isFalse);

      await handler.customActionDelegate!(kLikeAction, null);
      expect(container.read(favoritesProvider).containsKey(1), isTrue);
      expect(store.added, [1]);
      expect(handler.last.liked, isTrue);

      await handler.customActionDelegate!(kLikeAction, null);
      expect(container.read(favoritesProvider).containsKey(1), isFalse);
      expect(handler.last.liked, isFalse);
    });

    test('the liked state follows the song', () async {
      build();
      await notifier().playSong(lib, contextList: [lib, other]);
      await handler.customActionDelegate!(kLikeAction, null);
      await notifier().playSong(other, contextList: [lib, other]);
      await pump();
      expect(handler.last.liked, isFalse);
      await notifier().playSong(lib, contextList: [lib, other]);
      await pump();
      expect(handler.last.liked, isTrue);
    });

    test(
      'like does nothing when nothing plays or the song is external',
      () async {
        build();
        await handler.customActionDelegate!(kLikeAction, null);
        expect(container.read(favoritesProvider), isEmpty);

        await notifier().playSong(external, contextList: [external]);
        await pump();
        expect(handler.last.canLike, isFalse);
        await handler.customActionDelegate!(kLikeAction, null);
        expect(container.read(favoritesProvider), isEmpty);
        expect(store.added, isEmpty);
      },
    );

    test('shuffle and repeat call the player notifier', () async {
      build();
      await notifier().playSong(lib, contextList: [lib, other]);
      await handler.customActionDelegate!(kShuffleAction, null);
      expect(container.read(playerProvider).isShuffleModeEnabled, isTrue);
      expect(player.shuffled, isTrue);
      await pump();
      expect(handler.last.shuffle, isTrue);

      await handler.customActionDelegate!(kRepeatAction, null);
      expect(container.read(playerProvider).loopMode, LoopMode.all);
      await pump();
      expect(handler.last.repeat, LoopMode.all);
      await handler.customActionDelegate!(kRepeatAction, null);
      expect(handler.last.repeat, LoopMode.one);
      await handler.customActionDelegate!(kRepeatAction, null);
      expect(handler.last.repeat, LoopMode.off);
    });

    test('an unknown action is ignored', () async {
      build();
      await handler.customActionDelegate!('something_else', null);
      expect(container.read(favoritesProvider), isEmpty);
    });

    test('settings rebuild the controls', () async {
      build();
      final n = container.read(settingsProvider.notifier);
      await n.toggleNotifShuffle(true);
      expect(handler.last.shuffleEnabled, isTrue);
      await n.toggleNotifRepeat(true);
      expect(handler.last.repeatEnabled, isTrue);
      await n.toggleNotifLike(false);
      expect(handler.last.likeEnabled, isFalse);
    });

    test('the delegate is removed when the wiring is disposed', () {
      build();
      expect(handler.customActionDelegate, isNotNull);
      container.dispose();
      expect(handler.customActionDelegate, isNull);
    });
  });

  group('settings', () {
    test('defaults: Like on, Shuffle and Repeat off', () {
      const s = SettingsState();
      expect(
        [s.notifLike, s.notifShuffle, s.notifRepeat],
        [true, false, false],
      );
    });

    test('toggles persist', () async {
      final a = ProviderContainer();
      addTearDown(a.dispose);
      final n = a.read(settingsProvider.notifier);
      await n.toggleNotifLike(false);
      await n.toggleNotifShuffle(true);
      await n.toggleNotifRepeat(true);

      final b = ProviderContainer();
      addTearDown(b.dispose);
      await b.read(settingsProvider.notifier).load();
      final s = b.read(settingsProvider);
      expect([s.notifLike, s.notifShuffle, s.notifRepeat], [false, true, true]);
    });
  });
}

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final SettingsState initial;
  @override
  SettingsState build() => initial;
}
