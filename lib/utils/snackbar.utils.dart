import 'package:flutter/material.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/theme/aqua_widgets.dart';

/// Toasts: a Mac OS X heads-up panel that floats above the navigation. A new
/// toast replaces the one showing.
class AppSnackbar {
  /// A plain notice.
  static void showSnackbar(String title, String subtitle) =>
      _show(title, subtitle, ToastKind.info);

  /// Something was done: the orb carries a check mark.
  static void showSuccess(String title, String subtitle) =>
      _show(title, subtitle, ToastKind.success);

  /// Something went wrong: the orb is red.
  static void showErrorSnackBar(String title, String subtitle) =>
      _show(title, subtitle, ToastKind.error);

  static void _show(String title, String subtitle, ToastKind kind) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          // The toast draws its own panel.
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          duration: const Duration(seconds: 3),
          dismissDirection: DismissDirection.down,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: AquaToast(title: title, subtitle: subtitle, kind: kind),
        ),
      );
  }
}
