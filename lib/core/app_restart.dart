import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _appChannel = MethodChannel('com.mirimomekiku.wavvy/app');

/// Relaunches Wavvy in a fresh process. If the platform can't, the app is
/// closed instead so the user only has to open it again.
Future<void> restartApp() async {
  try {
    await _appChannel.invokeMethod<void>('restart');
  } on PlatformException catch (e) {
    debugPrint('restart failed: $e');
    await SystemNavigator.pop();
  } on MissingPluginException {
    await SystemNavigator.pop();
  }
}
