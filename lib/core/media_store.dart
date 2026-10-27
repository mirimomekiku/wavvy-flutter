import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Android scoped-storage operations on audio files, done through the system
/// consent dialogs instead of raw file access.
class MediaStoreChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.mirimomekiku.wavvy/media_store',
  );

  /// Deletes the audio file. Resolves true when it is gone, false when the user
  /// declined or nothing was deleted. Throws [PlatformException] on failure.
  Future<bool> deleteAudio(int id) async =>
      await _channel.invokeMethod<bool>('deleteAudio', {'id': id}) ?? false;

  /// Asks for permission to modify the audio file (edit its tags). Resolves
  /// true when writing is allowed.
  Future<bool> requestWriteAccess(int id) async =>
      await _channel.invokeMethod<bool>('requestWriteAccess', {'id': id}) ??
      false;

  /// Refreshes MediaStore for [path] after the file changed. Best effort.
  Future<void> scanFile(String path) async {
    try {
      await _channel.invokeMethod<void>('scanFile', {'path': path});
    } on PlatformException catch (e) {
      debugPrint('scanFile failed: $e');
    } on MissingPluginException {
      // Not running on Android.
    }
  }
}

final mediaStoreProvider = Provider<MediaStoreChannel>(
  (ref) => MediaStoreChannel(),
);
