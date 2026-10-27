import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wavvy/core/app_context.dart';
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

/// Wv dialog shell: rounded surface, bold title, body, and a row of pill
/// buttons.
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

    return Dialog(
      backgroundColor: a.surfaceHigh,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ds.radiusXL),
        side: BorderSide(color: a.separator),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
            child: Text(
              title,
              style: TextStyle(
                color: a.text,
                fontSize: 24,
                fontFamily: 'WorkSans',
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
              ),
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 12),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: a.textSecondary, fontSize: 14),
                child: content,
              ),
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: actions,
              ),
            ),
        ],
      ),
    );
  }
}

/// Pill button for dialog action rows. Destructive actions fill with the
/// error color.
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
        return Semantics(
          button: true,
          enabled: onPressed != null,
          label: label,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96, minHeight: 48),
            child: Material(
              color: a.error,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: a.scheme.onError,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
        size: 44,
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
