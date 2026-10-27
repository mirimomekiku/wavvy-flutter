import 'package:flutter/material.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Aqua "HUD" toast: dark translucent rounded rectangle with white text and
/// a crisp light edge, like the classic Mac OS X volume/eject overlay.
class AppSnackbar {
  static void showSnackbar(String title, String subtitle) {
    _show(title, subtitle, const Color(0xE6202020));
  }

  static void showErrorSnackBar(String title, String subtitle) {
    _show(title, subtitle, const Color(0xE6501818));
  }

  static void _show(String title, String subtitle, Color background) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: background,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          duration: const Duration(seconds: 3),
          dismissDirection: DismissDirection.down,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ds.radiusM),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
  }
}
