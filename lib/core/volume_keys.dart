import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

/// The native side of "hold a volume key to skip". Overridden in tests.
///
/// Android only lets an app see the volume keys while its window has focus, so
/// this works only while Wavvy is on screen.
abstract class VolumeKeysChannel {
  /// Tells the native side whether it should take over the volume keys.
  Future<void> setEnabled(bool enabled);

  /// Called with "next" or "previous" when a volume key is held.
  set onSkip(void Function(String direction)? handler);
}

class MethodVolumeKeysChannel implements VolumeKeysChannel {
  static const _channel = MethodChannel('com.mirimomekiku.wavvy/volume_keys');

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } catch (e) {
      debugPrint('volume keys unavailable: $e');
    }
  }

  @override
  set onSkip(void Function(String direction)? handler) {
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'skip' && call.arguments is String) {
        handler(call.arguments as String);
      }
    });
  }
}

final volumeKeysChannelProvider = Provider<VolumeKeysChannel>(
  (ref) => MethodVolumeKeysChannel(),
);

/// Keeps the native volume-key handling in step with the setting and turns
/// its skip events into next / previous. Watch it once from the app root.
final volumeKeysProvider = Provider<void>((ref) {
  final channel = ref.read(volumeKeysChannelProvider);
  bool enabled() => ref.read(settingsProvider).volumeKeySkip;

  unawaited(channel.setEnabled(enabled()));
  ref.listen(settingsProvider.select((s) => s.volumeKeySkip), (_, on) {
    unawaited(channel.setEnabled(on));
  });

  channel.onSkip = (direction) {
    if (!enabled()) return;
    final player = ref.read(playerProvider.notifier);
    // previous() restarts the song when it is well in, like the notification.
    if (direction == 'next') {
      player.next();
    } else if (direction == 'previous') {
      player.previous();
    }
  };
  ref.onDispose(() {
    channel.onSkip = null;
    unawaited(channel.setEnabled(false));
  });
});
