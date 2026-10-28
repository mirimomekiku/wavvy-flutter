import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/player_sheets/layouts/hifi_meters.dart';
import 'package:wavvy/providers/player_sheet_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/providers/visualizer_provider.dart';
import 'package:wavvy/screens/settings/visualizer_setting.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// The two meters of the Hi-Fi deck in the full build, and the strip under
/// them ([trailing] sits at its end). While the Player page shows and the app
/// is in front, it turns on the visualizer's visible flag, and the meters read
/// the bass and the treble from its bands. Whenever real levels are not coming
/// (setting off, permission missing, device cannot) the meters become the time
/// gauges, and a "Live meters" button offers the visualizer's usual
/// permission flow where that can help.
///
/// Only built behind `kVisualizerAvailable`, so the Play build drops it.
class HifiLiveMeters extends ConsumerStatefulWidget {
  const HifiLiveMeters({super.key, required this.trailing});
  final Widget trailing;

  @override
  ConsumerState<HifiLiveMeters> createState() => _HifiLiveMetersState();
}

class _HifiLiveMetersState extends ConsumerState<HifiLiveMeters>
    with WidgetsBindingObserver {
  late final VisualizerNotifier _notifier = ref.read(
    visualizerProvider.notifier,
  );
  bool _foreground = true;
  bool _onPage = true;

  void _sync() => _notifier.setVisible(_onPage && _foreground);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifier.setVisible(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Another page of the sheet is showing: let the visualizer rest.
    final onPage = ref.watch(sheetPageIndexProvider.select((i) => i == 0));
    if (onPage != _onPage) {
      _onPage = onPage;
      _notifier.setVisible(_onPage && _foreground);
    }
    final enabled = ref.watch(
      settingsProvider.select((s) => s.enableVisualizer),
    );
    final status = ref.watch(visualizerProvider.select((s) => s.status));
    final live = enabled && status == VisualizerStatus.running;
    final needsPermission =
        enabled && status == VisualizerStatus.needsPermission;
    final blocked = ref.watch(visualizerProvider.select((s) => s.blocked));
    final Widget? button = !enabled
        ? _MeterButton(
            label: 'Live meters',
            tooltip: 'Turn on the audio visualizer to drive the meters',
            onPressed: () => setVisualizerEnabled(context, ref, true),
          )
        : needsPermission
        ? _MeterButton(
            label: blocked ? 'Open Settings' : 'Allow meters',
            tooltip: 'The meters need the microphone permission',
            onPressed: blocked
                ? _notifier.openSystemSettings
                : _notifier.grantPermission,
          )
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (live) const _LiveMeterPair() else const HifiTimeMeters(),
        const SizedBox(height: 10),
        Row(
          children: [
            if (button != null) Flexible(child: button),
            const Spacer(),
            widget.trailing,
          ],
        ),
      ],
    );
  }
}

/// BASS and TREBLE, from the low and the high bands. Only this rebuilds with
/// each frame; the needles then ease toward the new levels on their own.
class _LiveMeterPair extends ConsumerWidget {
  const _LiveMeterPair();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bands = ref.watch(visualizerProvider.select((s) => s.bands));
    final levels = hifiBandLevels(bands);
    return Row(
      children: [
        Expanded(
          child: HifiMeter(
            level: levels.bass,
            redZone: true,
            label: 'BASS',
            semanticsLabel: 'Bass level meter',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: HifiMeter(
            level: levels.treble,
            redZone: true,
            label: 'TREBLE',
            semanticsLabel: 'Treble level meter',
          ),
        ),
      ],
    );
  }
}

class _MeterButton extends StatelessWidget {
  const _MeterButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return WvButton(
      key: const Key('hifi_live_meters'),
      size: 34,
      tooltip: tooltip,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq_rounded, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
