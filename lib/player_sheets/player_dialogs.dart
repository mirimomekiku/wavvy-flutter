import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

Widget _aquaSheet(
  BuildContext context, {
  required String title,
  required Widget content,
  required List<Widget> actions,
}) {
  final a = Aqua.of(context);
  return Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
    child: Container(
      decoration: BoxDecoration(
        color: a.background,
        borderRadius: BorderRadius.circular(Ds.radiusM),
        border: Border.all(color: a.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AquaSectionBar(title: title),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: content,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions,
            ),
          ),
        ],
      ),
    ),
  );
}

void showSpeedDialog(WidgetRef ref) {
  final player = ref.read(audioPlayerProvider);
  showAppDialog(
    builder: (context) {
      final a = Aqua.of(context);
      return _aquaSheet(
        context,
        title: "Playback Speed",
        content: StreamBuilder<double>(
          stream: player.speedStream,
          builder: (context, snapshot) {
            double currentSpeed = snapshot.data ?? 1.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${currentSpeed.toStringAsFixed(2)}x",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: a.text,
                  ),
                ),
                Slider(
                  value: currentSpeed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 6, // Steps: 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
                  onChanged: (value) {
                    player.setSpeed(value);
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          GelButton(
            size: 32,
            width: 80,
            tooltip: "Reset",
            onPressed: () => player.setSpeed(1.0),
            child: const Text("Reset"),
          ),
          GelButton(
            primary: true,
            size: 32,
            width: 80,
            tooltip: "Done",
            onPressed: () => AppNav.pop(),
            child: const Text("Done"),
          ),
        ],
      );
    },
  );
}

void showSongInfoDialog(
  BuildContext context,
  WidgetRef ref,
  SongModel song,
  Color bgColor,
  Color textColor,
) {
  final info = ref.read(playerProvider.notifier).getSongInfo(song);
  showAppDialog(
    builder: (context) {
      final a = Aqua.of(context);
      return _aquaSheet(
        context,
        title: "Song Details",
        content: Text(info, style: TextStyle(color: a.text)),
        actions: [
          GelButton(
            primary: true,
            size: 32,
            width: 80,
            tooltip: "Close",
            onPressed: () => AppNav.pop(),
            child: const Text("Close"),
          ),
        ],
      );
    },
  );
}
