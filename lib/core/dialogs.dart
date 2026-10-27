import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Context-free dialog helpers (replace Get.dialog / Get.defaultDialog).

/// Shows [builder] in a dialog on the root navigator.
Future<T?> showAppDialog<T>({
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final context = appContext;
  if (context == null) return Future.value(null);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}

/// A Mac OS X alert window: a silver title bar with the red close light over
/// paper content, and a button bar of gel buttons along the bottom.
class WvDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;

  const WvDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final radius = BorderRadius.circular(10);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: a.surface,
            borderRadius: radius,
            border: Border.all(color: a.outline.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: a.dark ? 0.55 : 0.3),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title bar.
                Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  decoration: BoxDecoration(
                    gradient: a.chromeGradient,
                    border: Border(
                      bottom: BorderSide(
                        color: a.outline.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Close',
                        child: InkResponse(
                          onTap: () => Navigator.of(context).maybePop(),
                          radius: 20,
                          child: const SizedBox(
                            width: 40,
                            height: 36,
                            child: Center(child: AquaCloseLight()),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: a.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Balances the close light so the title stays centered.
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(
                        color: a.textSecondary,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                      child: content,
                    ),
                  ),
                ),
                if (actions.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    decoration: BoxDecoration(
                      color: a.surfaceHigh,
                      border: Border(top: BorderSide(color: a.separator)),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: actions,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A gel button for a dialog's button bar. The default (primary) button is
/// blue; a destructive one is red.
Widget wvDialogButton(
  String label,
  VoidCallback? onPressed, {
  bool primary = false,
  bool destructive = false,
}) {
  return Builder(
    builder: (context) {
      final a = Wv.of(context);
      if (destructive) {
        const radius = 16.0;
        final red = a.error;
        return Semantics(
          button: true,
          enabled: onPressed != null,
          label: label,
          child: ExcludeSemantics(
            child: Opacity(
              opacity: onPressed == null ? 0.55 : 1,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(radius),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.lerp(red, Colors.white, 0.45)!,
                        Color.lerp(red, Colors.white, 0.1)!,
                        red,
                        Color.lerp(red, Colors.white, 0.12)!,
                      ],
                      stops: const [0, 0.45, 0.52, 1],
                    ),
                    border: Border.all(
                      color: Color.lerp(red, Colors.black, 0.3)!,
                    ),
                  ),
                  child: InkWell(
                    onTap: onPressed,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 96,
                        minHeight: 36,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: a.scheme.onError,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              shadows: const [
                                Shadow(
                                  color: Color(0x66000000),
                                  offset: Offset(0, -1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      return WvButton(
        width: 96,
        size: 36,
        primary: primary,
        onPressed: onPressed,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    },
  );
}

/// Confirm / cancel dialog. [onConfirm] runs after the dialog is closed.
Future<void> showConfirmDialog({
  required String title,
  required String message,
  String confirmText = "OK",
  String cancelText = "Cancel",
  bool destructive = false,
  required FutureOr<void> Function() onConfirm,
}) async {
  final confirmed = await showAppDialog<bool>(
    builder: (context) => WvDialog(
      title: title,
      content: Text(message),
      actions: [
        wvDialogButton(cancelText, () => Navigator.of(context).pop(false)),
        wvDialogButton(
          confirmText,
          () => Navigator.of(context).pop(true),
          primary: !destructive,
          destructive: destructive,
        ),
      ],
    ),
  );
  if (confirmed == true) await onConfirm();
}
