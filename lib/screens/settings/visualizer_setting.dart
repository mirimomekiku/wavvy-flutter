import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/storage_permissions.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/providers/visualizer_provider.dart';

/// Turns the visualizer on or off. Turning it on asks for the microphone
/// permission (Android requires it to read Wavvy's own audio levels) and only
/// switches the setting on when it is granted. If the permission was refused
/// for good, offers the system settings and leaves the setting off.
Future<void> setVisualizerEnabled(
  BuildContext context,
  WidgetRef ref,
  bool enabled,
) async {
  final settings = ref.read(settingsProvider.notifier);
  if (!enabled) {
    await settings.toggleVisualizer(false);
    return;
  }
  final channel = ref.read(visualizerChannelProvider);
  final access = await channel.permission(request: true);
  if (access.isGranted) {
    await settings.toggleVisualizer(true);
    return;
  }
  await settings.toggleVisualizer(false);
  if (access != StorageAccess.blocked || !context.mounted) return;
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Microphone permission'),
      content: const Text(
        'The visualizer needs the microphone permission so Android lets '
        'Wavvy read its own audio levels. Nothing is recorded or sent '
        'anywhere. Allow it in the system settings to use the visualizer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
  if (open == true) await channel.openSettings();
}
