import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/playback/rates.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';

/// Speed and pitch controls. They are independent: changing speed keeps the
/// pitch you set, and vice versa.
void showSpeedDialog(WidgetRef ref) {
  final player = ref.read(audioPlayerProvider);

  /// Sets speed and pitch, and remembers them for this album or folder when
  /// that setting is on.
  Future<void> setRate({double? speed, double? pitch}) async {
    if (speed != null) await player.setSpeed(speed);
    if (pitch != null) await player.setPitch(pitch);
    final song = ref.read(playerProvider).currentSong;
    if (song != null && ref.read(settingsProvider).rememberRates) {
      await ref
          .read(playbackRatesProvider.notifier)
          .remember(song, PlaybackRate(player.speed, player.pitch));
    }
  }

  showAppDialog(
    builder: (context) {
      return WvDialog(
        title: "Speed & Pitch",
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RateControl(
              label: 'Speed',
              icon: Icons.speed_rounded,
              stream: player.speedStream,
              initial: player.speed,
              onChanged: (v) => setRate(speed: v),
            ),
            const SizedBox(height: 14),
            _RateControl(
              label: 'Pitch',
              icon: Icons.music_note_rounded,
              stream: player.pitchStream,
              initial: player.pitch,
              onChanged: (v) => setRate(pitch: v),
            ),
          ],
        ),
        actions: [
          wvDialogButton("Reset", () => setRate(speed: 1.0, pitch: 1.0)),
          wvDialogButton("Done", () => AppNav.pop(), primary: true),
        ],
      );
    },
  );
}

/// One rate (speed or pitch): name and LCD readout over an Aqua slider.
class _RateControl extends StatelessWidget {
  const _RateControl({
    required this.label,
    required this.icon,
    required this.stream,
    required this.initial,
    required this.onChanged,
  });
  final String label;
  final IconData icon;
  final Stream<double> stream;
  final double initial;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return StreamBuilder<double>(
      stream: stream,
      initialData: initial,
      builder: (context, snapshot) {
        final value = (snapshot.data ?? 1.0).clamp(0.5, 2.0);
        final changed = (value - 1.0).abs() > 0.001;
        final small = TextStyle(fontSize: 11, color: a.textSecondary);
        return Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: changed ? a.accent : a.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: a.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 64),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  alignment: Alignment.center,
                  decoration: a.lcdDecoration.copyWith(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    "${value.toStringAsFixed(2)}x",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: a.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Steps: 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0
            AquaSlider(
              value: value,
              min: 0.5,
              max: 2.0,
              divisions: 6,
              onChanged: onChanged,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0.5x', style: small),
                  Text('2x', style: small),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The song's file details as a striped key / value table.
void showSongDetailsDialog(SongModel song) {
  final rows = PlayerUtils.songDetails(song);
  showAppDialog(
    builder: (context) {
      final a = Wv.of(context);
      return WvDialog(
        title: "Song Details",
        content: SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: a.outline.withValues(alpha: 0.55)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    ColoredBox(
                      color: i.isOdd ? a.stripe : a.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 72,
                              child: Text(
                                rows[i].$1,
                                style: TextStyle(
                                  color: a.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                rows[i].$2,
                                style: TextStyle(
                                  color: a.text,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          wvDialogButton(
            "Copy path",
            () => Clipboard.setData(ClipboardData(text: song.data)),
          ),
          wvDialogButton("Close", () => AppNav.pop(), primary: true),
        ],
      );
    },
  );
}
