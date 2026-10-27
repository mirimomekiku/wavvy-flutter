import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/downloader/engine.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Shown in place of the online search until the downloader is set up: says
/// what will be downloaded, and does it on request.
class EngineSetupCard extends ConsumerWidget {
  const EngineSetupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final engine = ref.watch(engineProvider);
    final notifier = ref.read(engineProvider.notifier);

    final Widget body = switch (engine.state) {
      EngineState.unknown => const Center(child: AquaSpinner(size: 30)),
      EngineState.installing => Row(
        children: [
          const AquaSpinner(size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              engine.message,
              style: TextStyle(color: a.text, fontSize: 13.5),
            ),
          ),
        ],
      ),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            engine.state == EngineState.failed
                ? 'The downloader could not be set up'
                : 'Set up the downloader',
            style: TextStyle(
              color: a.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            engine.state == EngineState.failed
                ? engine.message
                : 'The first time, Wavvy downloads yt-dlp, the tool that finds '
                      'and saves audio from YouTube and other sites. It is kept '
                      'up to date automatically. A Wi-Fi connection is best.',
            style: TextStyle(
              color: engine.state == EngineState.failed
                  ? a.error
                  : a.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: WvButton(
              key: const Key('engine_setup'),
              primary: true,
              width: 130,
              size: 36,
              onPressed: notifier.install,
              child: Text(
                engine.state == EngineState.failed ? 'Try again' : 'Set up',
              ),
            ),
          ),
        ],
      ),
    };

    return AquaWindow(
      title: 'Downloader',
      subtitle: 'Powered by yt-dlp',
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      child: body,
    );
  }
}

/// The downloader's row in Settings: its status, and a button to set it up or
/// update yt-dlp.
class EngineSettingsRow extends ConsumerWidget {
  const EngineSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final engine = ref.watch(engineProvider);
    final notifier = ref.read(engineProvider.notifier);

    final subtitle = switch (engine.state) {
      EngineState.unknown => 'Checking…',
      EngineState.missing => 'Not set up yet',
      EngineState.installing => engine.message,
      EngineState.failed => engine.message,
      EngineState.ready =>
        engine.message.isNotEmpty
            ? engine.message
            : 'yt-dlp ${engine.version ?? ''}'.trim(),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(Icons.cloud_download_outlined, color: a.textSecondary),
      title: const Text('Downloader', style: TextStyle(fontSize: 14)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color:
              engine.state == EngineState.failed ||
                  engine.message.startsWith('Update failed')
              ? a.error
              : null,
        ),
      ),
      trailing: engine.isBusy
          ? const AquaSpinner(size: 22)
          : WvButton(
              key: const Key('engine_action'),
              width: 90,
              size: 32,
              primary: !engine.isReady,
              onPressed: notifier.install,
              child: Text(engine.isReady ? 'Update' : 'Set up'),
            ),
    );
  }
}
