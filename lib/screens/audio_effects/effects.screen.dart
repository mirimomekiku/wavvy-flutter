import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

class AudioEffectsScreen extends StatelessWidget {
  const AudioEffectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: a.background,
        body: SafeArea(
          child: Column(
            children: [
              AquaBar(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      GelButton(
                        circular: true,
                        size: 32,
                        tooltip: "Back",
                        onPressed: () => AppNav.pop(),
                        child: const Icon(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        child: Text(
                          "Audio Control",
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: a.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(
                                color: Colors.white.withValues(
                                  alpha: a.dark ? 0.0 : 0.8,
                                ),
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Balances the back button so the title stays centered.
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
              Builder(
                builder: (context) {
                  final tabs = DefaultTabController.of(context);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AnimatedBuilder(
                      animation: tabs.animation!,
                      builder: (context, _) => AquaSegmented(
                        labels: const ["Equalizer", "Effects"],
                        selected: tabs.index,
                        onChanged: (i) => tabs.animateTo(i),
                      ),
                    ),
                  );
                },
              ),
              const Expanded(
                child: TabBarView(children: [_EqualizerTab(), _EffectsTab()]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// TAB 1: EQUALIZER
// ==========================================
class _EqualizerTab extends ConsumerWidget {
  const _EqualizerTab();

  static const double _pillHeight = 26;
  static const double _pillGap = 10;
  static const double _freqHeight = 18;
  static const double _freqGap = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EqualizerState eq = ref.watch(equalizerProvider);
    final EqualizerNotifier controller = ref.read(equalizerProvider.notifier);
    final a = Aqua.of(context);

    {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: InsetGroup(
              children: [
                // Enable
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Enable Equalizer",
                          style: TextStyle(
                            color: a.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      AquaCheckbox(
                        value: eq.isEnabled,
                        onChanged: (val) => controller.toggleEnabled(val),
                      ),
                    ],
                  ),
                ),
                // Preset selector
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Preset",
                          style: TextStyle(
                            color: a.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: "Choose preset",
                        onSelected: controller.applyPreset,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Ds.radiusM),
                          side: BorderSide(color: a.border),
                        ),
                        itemBuilder: (context) {
                          return EqualizerNotifier.presets.keys.map((String choice) {
                            return PopupMenuItem<String>(
                              value: choice,
                              child: Text(
                                choice,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList();
                        },
                        child: _PresetButton(
                          label: eq.currentPreset,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Bands Sliders
          Expanded(
            child: eq.bands.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GelButton(
                          circular: true,
                          size: 72,
                          onPressed: null,
                          child: const Icon(Icons.equalizer_rounded),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "EQ Not Available",
                          style: TextStyle(
                            color: a.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    decoration: BoxDecoration(
                      color: a.stripe,
                      borderRadius: BorderRadius.circular(Ds.radiusM),
                      border: Border.all(color: a.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        _buildScale(eq, a),
                        Container(width: 1, color: a.separator),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: List.generate(eq.bands.length, (
                                index,
                              ) {
                                return _buildSliderColumn(
                                  context,
                                  eq,
                                  controller,
                                  index,
                                  eq.isEnabled,
                                );
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      );
    }
  }

  /// dB scale (max / 0 / min) shown to the left of the bands, like iTunes.
  Widget _buildScale(EqualizerState controller, AquaPalette a) {
    final minDb = controller.minDecibels;
    final maxDb = controller.maxDecibels;
    String fmt(double v) => "${v > 0 ? '+' : ''}${v.toStringAsFixed(0)} dB";
    final style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: a.textSecondary,
    );

    return SizedBox(
      width: 52,
      child: Column(
        children: [
          const SizedBox(height: _pillHeight + _pillGap + 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fmt(maxDb), style: style),
                Text("0 dB", style: style),
                Text(fmt(minDb), style: style),
              ],
            ),
          ),
          const SizedBox(height: _freqHeight + _freqGap + 8),
        ],
      ),
    );
  }

  Widget _buildSliderColumn(
    BuildContext context,
    EqualizerState eq,
    EqualizerNotifier controller,
    int index,
    bool isEnabled,
  ) {
    final a = Aqua.of(context);
    final band = eq.bands[index];
    final freqHz = band.centerFrequency;
    String freqLabel = freqHz >= 1000
        ? "${(freqHz / 1000).toStringAsFixed(0)}k"
        : "${freqHz.toInt()}";

    return StreamBuilder<double>(
      stream: band.gainStream,
      initialData: band.gain,
      builder: (context, snapshot) {
        final gainMb = snapshot.data ?? 0.0;
        final currentGainDb = gainMb / 100.0;
        final minDb = eq.minDecibels;
        final maxDb = eq.maxDecibels;
        final safeSliderValue = currentGainDb.clamp(minDb, maxDb);
        final textColor = isEnabled ? a.text : a.textSecondary;

        return SizedBox(
          width: 52,
          child: Column(
            children: [
              const SizedBox(height: 8),
              SizedBox(
                height: _pillHeight,
                child: AquaLcd(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        "${safeSliderValue > 0 ? '+' : ''}${safeSliderValue.toStringAsFixed(1)}",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _pillGap),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: safeSliderValue,
                    min: minDb,
                    max: maxDb,
                    onChanged: isEnabled
                        ? (val) => controller.setBandGain(index, val)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: _freqGap),
              SizedBox(
                height: _freqHeight,
                child: Text(
                  freqLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Gel capsule that shows the current preset; used as the child of a
/// [PopupMenuButton] (which supplies the tap handling).
class _PresetButton extends StatelessWidget {
  final String label;

  const _PresetButton({required this.label});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            gradient: Aqua.gel(a.gelGray),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: a.gelBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: a.dark ? 0.06 : 0.7),
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: a.glyph,
                ),
              ),
              Icon(Icons.unfold_more_rounded, size: 18, color: a.glyph),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// TAB 2: NATIVE EFFECTS
// ==========================================
class _EffectsTab extends ConsumerWidget {
  const _EffectsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EffectsState fx = ref.watch(effectsProvider);
    final EffectsNotifier controller = ref.read(effectsProvider.notifier);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AquaSectionBar(
            title: "Dynamics",
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GelButton(
                circular: true,
                size: 28,
                tooltip: "Reset Effects",
                onPressed: () {
                  controller.setBassBoost(0.0);
                  controller.setVirtualizer(0.0);
                  controller.setReverb("None");
                },
                child: const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: InsetGroup(
              children: [
                _buildEffectControl(
                  context,
                  title: "Bass Boost",
                  icon: Icons.speaker_group_rounded,
                  value: fx.bassBoostStrength,
                  enabled: fx.isBassBoostEnabled,
                  onChanged: (val) => controller.setBassBoost(val),
                ),
                _buildEffectControl(
                  context,
                  title: "Virtualizer",
                  icon: Icons.surround_sound_rounded,
                  value: fx.virtualizerStrength,
                  enabled: fx.isVirtualizerEnabled,
                  onChanged: (val) => controller.setVirtualizer(val),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildEffectControl(
    BuildContext context, {
    required String title,
    required IconData icon,
    required double value,
    required bool enabled,
    required Function(double) onChanged,
  }) {
    final a = Aqua.of(context);

    {
      final double normalizedValue = value / 1000;
      final bool isEnabled = enabled;
      final Color textColor = isEnabled ? a.text : a.textSecondary;

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Column(
          children: [
            Row(
              children: [
                Opacity(
                  opacity: isEnabled ? 1 : 0.5,
                  child: IconBadge(
                    icon: icon,
                    color: a.dark
                        ? const Color(0xFF4F7FC4)
                        : const Color(0xFF3C84DE),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  "${(normalizedValue * 100).toInt()}%",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Slider(value: normalizedValue, onChanged: onChanged),
          ],
        ),
      );
    }
  }
}
