import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tells the home-screen widget what is playing.
abstract class HomeWidgetBridge {
  /// [art] is a JPEG, an empty list for "no artwork", or null to keep the
  /// picture the widget already has.
  Future<void> update({
    required String title,
    required String artist,
    required bool playing,
    Uint8List? art,
  });
}

class PlatformHomeWidget implements HomeWidgetBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.mirimomekiku.wavvy/widget',
  );

  @override
  Future<void> update({
    required String title,
    required String artist,
    required bool playing,
    Uint8List? art,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', {
        'title': title,
        'artist': artist,
        'playing': playing,
        'art': art,
      });
    } on PlatformException catch (e) {
      debugPrint('widget update failed: $e');
    } on MissingPluginException {
      // Not running on Android.
    }
  }
}

final homeWidgetProvider = Provider<HomeWidgetBridge>(
  (ref) => PlatformHomeWidget(),
);
