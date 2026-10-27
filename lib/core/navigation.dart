import 'package:flutter/cupertino.dart';
import 'package:wavvy/core/app_context.dart';

/// Context-free navigation (replaces Get.to / Get.toNamed / Get.back).
class AppNav {
  AppNav._();

  /// Pushes [page] with the Cupertino slide transition.
  static Future<T?> push<T>(Widget page) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.push<T>(CupertinoPageRoute<T>(builder: (_) => page));
  }

  /// Pushes a route registered in MaterialApp.routes.
  static Future<T?> pushNamed<T>(String routeName) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.pushNamed<T>(routeName);
  }

  /// Pops the top route (page, dialog or sheet).
  static void pop<T>([T? result]) {
    navigatorKey.currentState?.pop<T>(result);
  }
}
