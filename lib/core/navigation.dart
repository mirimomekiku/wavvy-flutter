import 'package:flutter/material.dart';
import 'package:wavvy/core/app_context.dart';

/// Context-free navigation through the app's navigator key.
class AppNav {
  AppNav._();

  /// Pushes [page] using the theme's page transition.
  static Future<T?> push<T>(Widget page) {
    final nav = navigatorKey.currentState;
    if (nav == null) return Future.value(null);
    return nav.push<T>(MaterialPageRoute<T>(builder: (_) => page));
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
