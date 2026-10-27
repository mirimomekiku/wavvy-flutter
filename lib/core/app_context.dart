import 'package:flutter/material.dart';

/// App-wide keys that replace GetX's context-free navigation, dialogs and
/// snackbars. They are wired into [MaterialApp] in main.dart.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// The navigator's current context (null before the first frame).
BuildContext? get appContext => navigatorKey.currentContext;
