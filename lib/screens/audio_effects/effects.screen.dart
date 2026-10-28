import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/widgets/status_message.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// Sound: the equalizer and the audio effects, as Mac OS X windows under a
/// unified toolbar that paints behind the status bar like the other tabs.
class AudioEffectsScreen extends StatelessWidget {
  const AudioEffectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);

    return WvSystemUi(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: a.pageColor,
          bottomNavigationBar: const BottomMiniPlayer(showTabView: false),
          // No SafeArea: the heading pads itself below the status bar so its
          // toolbar paints behind it.
          body: const Column(
            children: [
              WvPageHeading(
                title: 'Sound',
                subtitle: 'Fine-tune your listening.',
                back: true,
                bottom: _SoundTabs(),
              ),
              Expanded(
                child: TabBarView(children: [_EqualizerTab(), _EffectsTab()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Equalizer / Effects switch in the toolbar.
class _SoundTabs extends StatelessWidget {
  const _SoundTabs();

  @override
  Widget build(BuildContext context) {
    final tabs = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: tabs.animation!,
      builder: (context, _) => WvChips(
        labels: const ['Equalizer', 'Effects'],
        selected: tabs.index,
        onChanged: tabs.animateTo,
      ),
    );
  }
}

/// A label and a control on one line, wrapping the label before it overflows.
class _Line extends StatelessWidget {
  const _Line({required this.title, this.subtitle, required this.trailing});
  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: a.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: a.textSecondary,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    );
  }
}

/// An Aqua pop-up button: the current value on a gel capsule, a menu of
/// [options] below it. [display] turns an option into its label.
class _PopUp extends StatelessWidget {
  const _PopUp({
    required this.options,
    required this.value,
    required this.onSelected,
    this.display,
    this.enabled = true,
  });
  final List<String> options;
  final String value;
  final ValueChanged<String>? onSelected;
  final String Function(String)? display;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    String label(String v) => display?.call(v) ?? v;
    final face = AquaPopupLabel(label: label(value));
    if (!enabled || onSelected == null) {
      return Opacity(opacity: 0.55, child: face);
    }
    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      initialValue: value,
      color: a.surface,
      elevation: 6,
      shape: aquaMenuShape(a),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final o in options)
          CheckedPopupMenuItem(
            value: o,
            checked: o == value,
            child: Text(label(o)),
          ),
      ],
      child: face,
    );
  }
}

// ==========================================================================
// Equalizer
// ==========================================================================
class _EqualizerTab extends ConsumerWidget {
  const _EqualizerTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(equalizerProvider);
    final controller = ref.read(equalizerProvider.notifier);
    final a = Wv.of(context);
    final presets = eq.presetNames;
    final isCustom = eq.customPresets.containsKey(eq.currentPreset);
    final hasBands = eq.bands.isNotEmpty;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        0,
        16,
        0,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        AquaWindow(
          title: 'Equalizer',
          subtitle: eq.isEnabled ? 'On' : 'Off',
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Line(
                title: 'Enable equalizer',
                subtitle: 'Shape the sound band by band',
                trailing: AquaSwitch(
                  value: eq.isEnabled,
                  onChanged: hasBands ? controller.toggleEnabled : null,
                ),
              ),
              Divider(height: 24, color: a.separator),
              _Line(
                title: 'Preset',
                trailing: _PopUp(
                  options: presets,
                  value: eq.currentPreset,
                  enabled: hasBands,
                  onSelected: controller.applyPreset,
                ),
              ),
              if (hasBands) ...[
                const SizedBox(height: 12),
                _Line(
                  title: isCustom ? 'Your preset' : 'Save these settings',
                  subtitle: isCustom
                      ? eq.currentPreset
                      : 'Keep the current bands as a preset',
                  trailing: isCustom
                      ? WvButton(
                          size: 36,
                          onPressed: () =>
                              controller.deleteCustomPreset(eq.currentPreset),
                          child: const Text('Delete'),
                        )
                      : WvButton(
                          size: 36,
                          onPressed: () => _askPresetName(context, controller),
                          child: const Text('Save…'),
                        ),
                ),
              ],
              Divider(height: 24, color: a.separator),
              _Line(
                title: 'Prevent clipping',
                subtitle: eq.autoPreamp && eq.preampDb < 0
                    ? 'Volume lowered ${(-eq.preampDb).toStringAsFixed(1)} dB for the boosted bands'
                    : 'Lower the volume by the biggest boost so it does not distort',
                trailing: AquaSwitch(
                  value: eq.autoPreamp,
                  onChanged: hasBands ? controller.setAutoPreamp : null,
                ),
              ),
              if (eq.error.isNotEmpty && hasBands)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    eq.error,
                    style: TextStyle(color: a.error, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        AquaWindow(
          title: 'Bands',
          subtitle: hasBands
              ? '${eq.minDecibels.toStringAsFixed(0)} to +${eq.maxDecibels.toStringAsFixed(0)} dB'
              : null,
          action: hasBands ? 'Flatten' : null,
          onAction: hasBands ? controller.resetToFlat : null,
          child: hasBands
              ? _Bands(eq: eq, controller: controller)
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: WvStatusMessage(
                    icon: Icons.equalizer_rounded,
                    title: 'Equalizer not available',
                    message: eq.error.isEmpty
                        ? 'This device does not provide an equalizer.'
                        : eq.error,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Asks for a name, then saves the current bands as a preset.
void _askPresetName(BuildContext context, EqualizerNotifier controller) {
  showDialog<void>(
    context: context,
    builder: (_) => _PresetNameDialog(controller: controller),
  );
}

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.controller});
  final EqualizerNotifier controller;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _name = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = await widget.controller.saveCustomPreset(_name.text);
    if (!mounted) return;
    if (problem == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _problem = problem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return WvDialog(
      title: 'Save preset',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AquaField(
            label: 'Preset name',
            controller: _name,
            textInputAction: TextInputAction.done,
          ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _problem!,
                style: TextStyle(color: a.error, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        wvDialogButton('Cancel', () => Navigator.of(context).pop()),
        wvDialogButton('Save', _save, primary: true),
      ],
    );
  }
}

/// The graphic equalizer: a dB scale and one vertical slider per band.
class _Bands extends StatelessWidget {
  const _Bands({required this.eq, required this.controller});
  final EqualizerState eq;
  final EqualizerNotifier controller;

  static const double _readoutHeight = 26;
  static const double _gap = 8;
  static const double _labelHeight = 18;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final height = 280 + MediaQuery.textScalerOf(context).scale(14);

    String fmt(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}';
    final scaleStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: a.textSecondary,
    );

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        child: Row(
          children: [
            // dB scale.
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  const SizedBox(height: _readoutHeight + _gap),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${fmt(eq.maxDecibels)} dB', style: scaleStyle),
                        Text('0 dB', style: scaleStyle),
                        Text('${fmt(eq.minDecibels)} dB', style: scaleStyle),
                      ],
                    ),
                  ),
                  const SizedBox(height: _gap + _labelHeight),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final width = (c.maxWidth / eq.bands.length).clamp(
                    56.0,
                    120.0,
                  );
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: c.maxWidth),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          for (var i = 0; i < eq.bands.length; i++)
                            SizedBox(
                              width: width,
                              child: _Band(
                                eq: eq,
                                controller: controller,
                                index: i,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({
    required this.eq,
    required this.controller,
    required this.index,
  });
  final EqualizerState eq;
  final EqualizerNotifier controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final band = eq.bands[index];
    final hz = band.centerFrequency;
    final label = hz >= 1000
        ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k'
        : '${hz.toInt()}';

    return StreamBuilder<double>(
      stream: band.gainStream,
      initialData: band.gain,
      builder: (context, snapshot) {
        // just_audio reports band gains in decibels.
        final db = (snapshot.data ?? 0.0).clamp(eq.minDecibels, eq.maxDecibels);
        return Column(
          children: [
            Container(
              height: _Bands._readoutHeight,
              width: 48,
              alignment: Alignment.center,
              decoration: a.lcdDecoration.copyWith(
                borderRadius: BorderRadius.circular(5),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${db > 0 ? '+' : ''}${db.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: eq.isEnabled ? a.text : a.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: _Bands._gap),
            Expanded(
              child: AquaVerticalSlider(
                value: db,
                min: eq.minDecibels,
                max: eq.maxDecibels,
                onChanged: eq.isEnabled
                    ? (v) => controller.setBandGain(index, v)
                    : null,
              ),
            ),
            const SizedBox(height: _Bands._gap),
            SizedBox(
              height: _Bands._labelHeight,
              child: Text(
                '$label Hz',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: eq.isEnabled ? a.text : a.textSecondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ==========================================================================
// Effects
// ==========================================================================
class _EffectsTab extends ConsumerWidget {
  const _EffectsTab();

  static String _reverbName(String value) => value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fx = ref.watch(effectsProvider);
    final controller = ref.read(effectsProvider.notifier);
    final a = Wv.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        0,
        16,
        0,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        AquaWindow(
          title: 'Dynamics',
          subtitle: 'Bass and stereo width',
          action: 'Reset',
          onAction: controller.resetAll,
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              if (fx.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fx.error,
                      style: TextStyle(color: a.error, fontSize: 12.5),
                    ),
                  ),
                ),
              _EffectRow(
                icon: Icons.speaker_group_rounded,
                title: 'Bass boost',
                value: fx.bassBoostStrength / 1000,
                supported: fx.support.bassBoost,
                onChanged: controller.setBassBoost,
              ),
              Divider(height: 26, color: a.separator),
              _EffectRow(
                icon: Icons.surround_sound_rounded,
                title: 'Virtualizer',
                value: fx.virtualizerStrength / 1000,
                supported: fx.support.virtualizer,
                onChanged: controller.setVirtualizer,
              ),
            ],
          ),
        ),
        AquaWindow(
          title: 'Reverb',
          padding: const EdgeInsets.all(14),
          child: _Line(
            title: 'Room',
            subtitle: fx.support.reverb
                ? 'Add a little space to the sound'
                : 'Not supported on this device',
            trailing: _PopUp(
              options: const [
                'None',
                'SmallRoom',
                'MediumRoom',
                'LargeRoom',
                'MediumHall',
                'LargeHall',
                'Plate',
              ],
              value: fx.currentReverbPreset,
              display: _reverbName,
              enabled: fx.support.reverb,
              onSelected: controller.setReverb,
            ),
          ),
        ),
        AquaWindow(
          title: 'Volume',
          padding: const EdgeInsets.all(14),
          child: _Line(
            title: 'Volume boost',
            subtitle:
                'Raise the overall volume by '
                '${EffectsNotifier.loudnessBoostDb.toStringAsFixed(0)} dB',
            trailing: AquaSwitch(
              value: fx.isLoudnessBoosted,
              onChanged: controller.setLoudnessBoost,
            ),
          ),
        ),
      ],
    );
  }
}

/// An effect's icon, name and percentage readout over an Aqua slider.
class _EffectRow extends StatelessWidget {
  const _EffectRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.supported,
    required this.onChanged,
  });
  final IconData icon;
  final String title;

  /// 0..1.
  final double value;
  final bool supported;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final lit = value > 0 && supported;
    return Opacity(
      opacity: supported ? 1 : 0.55,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: a.gelGradient(primary: lit),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: a.outline.withValues(alpha: 0.7)),
                ),
                child: Icon(icon, size: 18, color: lit ? a.onAccent : a.text),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: a.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 54),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                alignment: Alignment.center,
                decoration: a.lcdDecoration.copyWith(
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  supported ? '${(value * 100).round()}%' : 'N/A',
                  style: TextStyle(
                    color: a.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AquaSlider(value: value, onChanged: supported ? onChanged : null),
        ],
      ),
    );
  }
}
