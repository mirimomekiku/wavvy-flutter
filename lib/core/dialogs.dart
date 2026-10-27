import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/core/navigation.dart';
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

/// Aqua dialog shell: section-bar title, body, and a row of gel buttons.
class AquaDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;

  const AquaDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Dialog(
      backgroundColor: a.background,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Ds.radiusM + 2),
        side: BorderSide(color: a.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AquaSectionBar(title: title),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: a.text, fontSize: 14),
                child: content,
              ),
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (int i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    actions[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Labeled capsule gel button for dialog action rows.
Widget aquaDialogButton(
  String label,
  VoidCallback? onPressed, {
  bool primary = false,
  bool destructive = false,
}) {
  return GelButton(
    width: 92,
    primary: primary,
    onPressed: onPressed,
    child: Text(
      label,
      style: destructive
          ? TextStyle(
              color: Colors.red.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            )
          : null,
    ),
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
    builder: (context) => AquaDialog(
      title: title,
      content: Text(message),
      actions: [
        aquaDialogButton(cancelText, () => Navigator.of(context).pop(false)),
        aquaDialogButton(
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

/// Convenience for non-context code that only needs to close the top route.
void closeTopRoute() => AppNav.pop();
