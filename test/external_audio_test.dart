import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/external_audio.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/widgets/song_menu.dart';

import 'helpers/fake_player.dart';

class _FakeChannel implements ExternalAudioChannel {
  ExternalAudio? pending;
  int takes = 0;
  void Function(ExternalAudio)? handler;

  @override
  Future<ExternalAudio?> takePending() async {
    takes++;
    final p = pending;
    pending = null;
    return p;
  }

  @override
  set onOpen(void Function(ExternalAudio audio)? h) => handler = h;
}

class _Library extends LibraryNotifier {
  _Library(this.initial);
  final List<SongModel> initial;
  @override
  LibraryState build() => LibraryState(songs: initial, filteredSongs: initial);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryPlayer player;
  late _FakeChannel channel;

  ProviderContainer make({List<SongModel> library = const []}) {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    player = MemoryPlayer();
    channel = _FakeChannel();
    final container = ProviderContainer(
      overrides: [
        audioPlayerProvider.overrideWithValue(player),
        externalAudioChannelProvider.overrideWithValue(channel),
        libraryProvider.overrideWith(() => _Library(library)),
        externalAudioHandlerProvider.overrideWith(
          (ref) => ExternalAudioHandler(
            ref,
            libraryTimeout: const Duration(milliseconds: 250),
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await player.close();
    });
    return container;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('a library file plays inside the library queue', () async {
    final songs = [for (var i = 1; i <= 3; i++) testSong(i)];
    final container = make(library: songs);
    await container
        .read(externalAudioHandlerProvider)
        .open(
          const ExternalAudio(
            uri: 'content://media/external/audio/media/2',
            mediaId: 2,
          ),
        );
    expect(player.nativeOrder, [1, 2, 3]);
    expect(player.lastInitialIndex, 1);
    expect(container.read(playerProvider).currentSong?.id, 2);
  });

  test('an unknown file plays alone as a song with a negative id', () async {
    final container = make(library: [testSong(1)]);
    await container
        .read(externalAudioHandlerProvider)
        .open(
          const ExternalAudio(
            uri: 'content://docs/song%201.mp3',
            title: 'Hello',
            artist: 'Me',
            album: 'Album',
            durationMs: 61000,
            displayName: 'song 1.mp3',
          ),
        );
    expect(player.nativeOrder.length, 1);
    final song = container.read(playerProvider).currentSong!;
    expect(song.id, isNegative);
    expect(song.isExternal, isTrue);
    expect(song.uri, 'content://docs/song%201.mp3');
    expect(song.title, 'Hello');
    expect(song.artist, 'Me');
    expect(song.album, 'Album');
    expect(song.duration, 61000);
    expect(song.data, '');
    expect(player.playCalls, 1);
  });

  test('a MediaStore id missing from the loaded library plays alone', () async {
    final container = make(library: [testSong(1)]);
    await container
        .read(externalAudioHandlerProvider)
        .open(
          const ExternalAudio(
            uri: 'content://media/external/audio/media/99',
            mediaId: 99,
          ),
        );
    expect(player.nativeOrder.length, 1);
    expect(container.read(playerProvider).currentSong?.isExternal, isTrue);
  });

  test('missing metadata falls back to the file name', () async {
    final byName = ExternalAudioHandler.songFor(
      const ExternalAudio(uri: 'content://x/1', displayName: 'My Track.flac'),
    );
    expect(byName.title, 'My Track');
    expect(byName.fileExtension, 'flac');
    expect(byName.duration, isNull);

    final byUri = ExternalAudioHandler.songFor(
      const ExternalAudio(uri: 'file:///sdcard/Music/Night%20Drive.ogg'),
    );
    expect(byUri.title, 'Night Drive');
    expect(byUri.data, '/sdcard/Music/Night Drive.ogg');

    final bare = ExternalAudio.fromMap({'uri': 'content://x/1', 'title': '  '});
    expect(bare!.title, isNull);
    expect(ExternalAudio.fromMap({'uri': ''}), isNull);
    expect(ExternalAudio.fromMap(null), isNull);
  });

  test('ids are stable, negative and differ per URI', () {
    final a = ExternalAudioHandler.externalId('content://a/1');
    expect(ExternalAudioHandler.externalId('content://a/1'), a);
    expect(a, isNegative);
    expect(ExternalAudioHandler.externalId('content://a/2'), isNot(a));
  });

  test('the pending file is taken once and plays', () async {
    final container = make();
    channel.pending = const ExternalAudio(uri: 'content://docs/a.mp3');
    container.read(externalAudioProvider);
    await settle();
    expect(player.nativeOrder.length, 1);
    expect(channel.pending, isNull);

    // A second start finds nothing left to take.
    final plays = player.playCalls;
    expect(await channel.takePending(), isNull);
    expect(player.playCalls, plays);
  });

  test('a file opened while running plays too', () async {
    final container = make();
    container.read(externalAudioProvider);
    await settle();
    expect(player.nativeOrder, isEmpty);

    channel.handler!(const ExternalAudio(uri: 'content://docs/b.mp3'));
    await settle();
    channel.handler!(const ExternalAudio(uri: 'content://docs/c.mp3'));
    await settle();
    expect(player.nativeOrder.length, 1);
    expect(player.playCalls, 2);
    expect(
      container.read(playerProvider).currentSong?.uri,
      'content://docs/c.mp3',
    );
  });

  test('a file the player rejects does not throw', () async {
    final container = make();
    player.failNextLoad = true;
    await container
        .read(externalAudioHandlerProvider)
        .open(const ExternalAudio(uri: 'content://docs/bad.mp3'));
    expect(player.playCalls, 0);
  });

  testWidgets('the song menu hides Delete and Edit tags for external songs', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // Tall enough for the whole menu (the list builds only what is visible).
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final external = ExternalAudioHandler.songFor(
      const ExternalAudio(uri: 'content://docs/a.mp3', title: 'Outside'),
    );
    final inside = testSong(5);
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [libraryProvider.overrideWith(() => _Library(const []))],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              widgetRef = ref;
              return Column(
                children: [
                  TextButton(
                    onPressed: () => SongMenuHelper.show(
                      context,
                      ref,
                      external,
                      options: const SongMenuOptions(showDelete: true),
                    ),
                    child: const Text('external'),
                  ),
                  TextButton(
                    onPressed: () => SongMenuHelper.show(
                      context,
                      ref,
                      inside,
                      options: const SongMenuOptions(showDelete: true),
                    ),
                    child: const Text('inside'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    expect(widgetRef, isNotNull);

    await tester.tap(find.text('external'));
    await tester.pumpAndSettle();
    expect(find.text('Play Next'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Edit tags'), findsNothing);
    expect(find.text('Add to Favorites'), findsNothing);
    expect(find.text('Add to Playlist'), findsNothing);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('inside'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Edit tags'), findsOneWidget);
  });
}
