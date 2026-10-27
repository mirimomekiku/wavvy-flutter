import 'package:flutter/material.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Floating pill toast: inverse-surface colors, a tiny pixel sprite in a
/// squircle badge, a bold title and an optional subtitle. The error variant
/// uses the error color for the badge.
class AppSnackbar {
  static void showSnackbar(String title, String subtitle) {
    _show(title, subtitle, error: false);
  }

  static void showErrorSnackBar(String title, String subtitle) {
    _show(title, subtitle, error: true);
  }

  static void _show(String title, String subtitle, {required bool error}) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    final messengerContext = messengerKey.currentContext;
    final a = messengerContext == null
        ? WvPalette.fallback
        : Wv.of(messengerContext);
    final scheme = a.scheme;

    final badge = error ? a.error : scheme.inversePrimary;
    final sprite = error ? scheme.onError : scheme.inverseSurface;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: scheme.inverseSurface,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
          duration: const Duration(seconds: 3),
          dismissDirection: DismissDirection.down,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Ds.radiusXL),
          ),
          content: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badge,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: PixelSpriteView(
                  sprite: error ? PixelSprites.star : PixelSprites.note,
                  size: 22,
                  color: sprite,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onInverseSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: scheme.onInverseSurface.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}
