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

  /// Deletes several audio files, with one confirmation on Android 11+.
  /// Resolves with the ids that are gone (all of them, or none if the user
  /// declined). Throws [PlatformException] on failure.
  Future<List<int>> deleteAudios(List<int> ids) async {
    final result = await _channel.invokeMethod<Object?>('deleteAudios', {
      'ids': ids,
    });
    // Android 11+ answers for the whole request; older versions list what
    // they could delete.
    if (result is bool) return result ? ids : const [];
    if (result is List) return [for (final id in result) (id as num).toInt()];
    return const [];
  }

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
