import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

void showSpeedDialog(WidgetRef ref) {
  final player = ref.read(audioPlayerProvider);
  showAppDialog(
    builder: (context) {
      final a = Wv.of(context);
      return WvDialog(
        title: "Playback Speed",
        content: StreamBuilder<double>(
          stream: player.speedStream,
          builder: (context, snapshot) {
            double currentSpeed = snapshot.data ?? 1.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 12,
                  ),
                  decoration: a.frame(color: a.primaryContainer, radius: 16),
                  child: Text(
                    "${currentSpeed.toStringAsFixed(2)}x",
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      color: a.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
          wvDialogButton("Reset", () => player.setSpeed(1.0)),
          wvDialogButton("Done", () => AppNav.pop(), primary: true),
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
      final a = Wv.of(context);
      return WvDialog(
        title: "Song Details",
        content: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: a.frame(color: a.surfaceHighest, radius: 24),
            child: Text(
              info,
              style: TextStyle(color: a.text, fontSize: 14, height: 1.5),
            ),
          ),
        ),
        actions: [wvDialogButton("Close", () => AppNav.pop(), primary: true)],
      );
    },
  );
}
