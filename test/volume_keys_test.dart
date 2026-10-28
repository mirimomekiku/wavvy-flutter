import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wavvy/core/volume_keys.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

import 'helpers/fake_player.dart';

class _FakeKeys implements VolumeKeysChannel {
  final pushed = <bool>[];
  void Function(String)? handler;

  @override
  Future<void> setEnabled(bool enabled) async => pushed.add(enabled);

  @override
  set onSkip(void Function(String direction)? h) => handler = h;
}

/// A player that records how it was asked to skip.
class _SkipPlayer extends MemoryPlayer {
  int nexts = 0;
  int previouses = 0;

  @override
  bool get hasNext => true;
  @override
  bool get hasPrevious => true;
  @override
  Future<void> seekToNext() async => nexts++;
  @override
  Future<void> seekToPrevious() async => previouses++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeKeys keys;
  late _SkipPlayer player;
  late ProviderContainer container;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    keys = _FakeKeys();
    player = _SkipPlayer();
    container = ProviderContainer(
      overrides: [
        volumeKeysChannelProvider.overrideWithValue(keys),
        audioPlayerProvider.overrideWithValue(player),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await player.close();
    });
  });

  test('pushes the setting at start and whenever it changes', () async {
    container.read(volumeKeysProvider);
    expect(keys.pushed, [false]);

    await container.read(settingsProvider.notifier).toggleVolumeKeySkip(true);
    await container.read(settingsProvider.notifier).toggleVolumeKeySkip(false);
    expect(keys.pushed, [false, true, false]);
  });

  test('skip events call next and previous while the setting is on', () async {
    container.read(volumeKeysProvider);
    await container.read(settingsProvider.notifier).toggleVolumeKeySkip(true);

    keys.handler!('next');
    keys.handler!('previous');
    keys.handler!('sideways');
    expect(player.nexts, 1);
    expect(player.previouses, 1);
  });

  test('skip events are ignored while the setting is off', () {
    container.read(volumeKeysProvider);
    keys.handler!('next');
    keys.handler!('previous');
    expect(player.nexts, 0);
    expect(player.previouses, 0);
  });

  test('disposing detaches the handler and turns the keys off', () async {
    container.read(volumeKeysProvider);
    await container.read(settingsProvider.notifier).toggleVolumeKeySkip(true);
    container.dispose();
    expect(keys.handler, isNull);
    expect(keys.pushed.last, isFalse);
  });
}
