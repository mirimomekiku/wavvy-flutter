import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of asking for a storage-related permission.
enum StorageAccess {
  granted,

  /// Refused, but the system will still show its prompt.
  denied,

  /// Refused for good: only the system settings can change it now.
  blocked;

  bool get isGranted => this == granted;
}

/// Runtime storage permissions, resolved per Android version.
///
///  * Android 13+: media access is `READ_MEDIA_AUDIO`.
///  * Android 6-12: `READ_EXTERNAL_STORAGE`.
///  * Android 9 and below: the same permission also covers writing files.
///  * Android 10+: no permission covers editing or deleting other apps' media;
///    that goes through the MediaStore consent dialogs (see `media_store.dart`).
class StoragePermissions {
  StoragePermissions._();

  static int? _sdk;

  /// The Android API level, or 0 off Android.
  static Future<int> sdkInt() async {
    if (!Platform.isAndroid) return 0;
    return _sdk ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  }

  static StorageAccess _classify(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return StorageAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return StorageAccess.blocked;
    }
    return StorageAccess.denied;
  }

  static Future<StorageAccess> _ensure(
    Permission permission, {
    required bool request,
  }) async {
    var status = await permission.status;
    if (!status.isGranted && request && !status.isPermanentlyDenied) {
      status = await permission.request();
    }
    return _classify(status);
  }

  /// Access to the device music library. With [request] false only the
  /// current grant is checked (used for silent reloads).
  static Future<StorageAccess> musicLibrary({bool request = true}) async {
    if (!Platform.isAndroid) return StorageAccess.granted;
    final sdk = await sdkInt();
    return _ensure(
      sdk >= 33 ? Permission.audio : Permission.storage,
      request: request,
    );
  }

  /// Playback notification controls. Optional: the result is not needed.
  static Future<void> requestNotifications() async {
    if (!Platform.isAndroid || await sdkInt() < 33) return;
    await _ensure(Permission.notification, request: true);
  }

  /// Writing into shared storage. Only Android 9 and below need a permission;
  /// newer versions write downloads through the system downloader.
  static Future<StorageAccess> legacyWrite({bool request = true}) async {
    if (!Platform.isAndroid || await sdkInt() > 28) {
      return StorageAccess.granted;
    }
    return _ensure(Permission.storage, request: request);
  }
}
