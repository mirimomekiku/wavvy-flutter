import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/audio_effects_provider.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/widgets/bottom_bar.dart';

class AudioEffectsScreen extends StatelessWidget {
  const AudioEffectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: a.background,
        bottomNavigationBar: const BottomMiniPlayer(showTabView: false),
        body: SafeArea(
          child: Column(
            children: [
              const WvPageHeading(
                title: 'Sound',
                subtitle: 'Fine-tune your listening.',
                back: true,
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final tabs = DefaultTabController.of(context);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AnimatedBuilder(
                      animation: tabs.animation!,
                      builder: (context, _) => WvChips(
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
    final a = Wv.of(context);

    {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 12),
              decoration: a.frame(
                color: a.primaryContainer,
                radius: Ds.radiusXL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Enable Equalizer",
                          style: TextStyle(
                            color: a.onPrimaryContainer,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      WvSwitch(
                        value: eq.isEnabled,
                        onChanged: (val) => controller.toggleEnabled(val),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: WvChips(
                      labels: EqualizerNotifier.presets.keys.toList(),
                      selected: EqualizerNotifier.presets.keys.toList().indexOf(
                        eq.currentPreset,
                      ),
                      onChanged: (i) => controller.applyPreset(
                        EqualizerNotifier.presets.keys.elementAt(i),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bands Sliders
          Expanded(
            child: eq.bands.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const WvSymbol(
                          sprite: PixelSprites.mascotSleepy,
                          size: 72,
                          themed: true,
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
                    decoration: a.frame(color: a.surface, radius: Ds.radiusXL),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        _buildScale(eq, a),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: List.generate(eq.bands.length, (index) {
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

  /// dB scale (max / 0 / min) shown to the left of the bands.
  Widget _buildScale(EqualizerState controller, WvPalette a) {
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
    final a = Wv.of(context);
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
                child: WvPanel(
                  radius: 13,
                  color: isEnabled ? a.primaryContainer : a.surfaceHigh,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        "${safeSliderValue > 0 ? '+' : ''}${safeSliderValue.toStringAsFixed(1)}",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isEnabled ? a.onPrimaryContainer : textColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _pillGap),
              Expanded(
                child: _BandMeter(
                  value: safeSliderValue,
                  min: minDb,
                  max: maxDb,
                  color: isEnabled ? a.accent : a.textTertiary,
                  trackColor: a.surfaceHighest,
                  onChanged: isEnabled
                      ? (val) => controller.setBandGain(index, val)
                      : null,
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

/// Pixel-block level meter for one EQ band. Tap or drag vertically to set the
/// gain; blocks fill from the bottom up to the current level.
class _BandMeter extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final Color color;
  final Color trackColor;
  final ValueChanged<double>? onChanged;

  const _BandMeter({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.trackColor,
    required this.onChanged,
  });

  double _fromDy(double dy, double height) {
    if (height <= 0 || max <= min) return min;
    final t = 1 - (dy / height).clamp(0.0, 1.0);
    return min + (max - min) * t;
  }

  @override
  Widget build(BuildContext context) {
    final span = max - min;
    final fraction = span <= 0 ? 0.0 : ((value - min) / span).clamp(0.0, 1.0);
    final step = span <= 0 ? 0.0 : span / 20;

    return Semantics(
      slider: true,
      value: "${value.toStringAsFixed(1)} dB",
      increasedValue: "${(value + step).clamp(min, max).toStringAsFixed(1)} dB",
      decreasedValue: "${(value - step).clamp(min, max).toStringAsFixed(1)} dB",
      onIncrease: onChanged == null
          ? null
          : () => onChanged!((value + step).clamp(min, max)),
      onDecrease: onChanged == null
          ? null
          : () => onChanged!((value - step).clamp(min, max)),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.hasBoundedHeight ? c.maxHeight : 160.0;
            void set(double dy) => onChanged?.call(_fromDy(dy, h));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: onChanged == null
                  ? null
                  : (d) => set(d.localPosition.dy),
              onVerticalDragUpdate: onChanged == null
                  ? null
                  : (d) => set(d.localPosition.dy),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: h,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _MeterPainter(fraction, color, trackColor),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.fraction, this.color, this.track);
  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const gap = 2.0;
    final blocks = (size.height / 12).floor().clamp(4, 40);
    final bh = (size.height - gap * (blocks - 1)) / blocks;
    if (bh <= 0) return;
    final filled = (fraction * blocks).round();
    final paint = Paint()..isAntiAlias = false;
    for (var i = 0; i < blocks; i++) {
      final top = (size.height - (i + 1) * bh - i * gap).roundToDouble();
      final rect = Rect.fromLTWH(0, top, size.width, bh.roundToDouble());
      canvas.drawRect(rect, paint..color = i < filled ? color : track);
    }
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
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
          WvSectionHeader(
            title: "Dynamics",
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: WvButton(
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
            child: Column(
              children: [
                _buildEffectControl(
                  context,
                  index: 0,
                  title: "Bass Boost",
                  icon: Icons.speaker_group_rounded,
                  value: fx.bassBoostStrength,
                  enabled: fx.isBassBoostEnabled,
                  onChanged: (val) => controller.setBassBoost(val),
                ),
                const SizedBox(height: 10),
                _buildEffectControl(
                  context,
                  index: 1,
                  title: "Virtualizer",
                  icon: Icons.surround_sound_rounded,
                  value: fx.virtualizerStrength,
                  enabled: fx.isVirtualizerEnabled,
                  onChanged: (val) => controller.setVirtualizer(val),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: fx.currentReverbPreset,
                  decoration: const InputDecoration(
                    labelText: 'Reverb',
                    helperText: 'Add a little room to the sound',
                  ),
                  items:
                      const [
                            'None',
                            'SmallRoom',
                            'MediumRoom',
                            'LargeRoom',
                            'MediumHall',
                            'LargeHall',
                            'Plate',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value.replaceAllMapped(
                                  RegExp(r'([a-z])([A-Z])'),
                                  (m) => '${m[1]} ${m[2]}',
                                ),
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) controller.setReverb(value);
                  },
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
    required int index,
    required String title,
    required IconData icon,
    required double value,
    required bool enabled,
    required Function(double) onChanged,
  }) {
    final a = Wv.of(context);

    final (bg, fg) = a.tonal(index);
    final double normalizedValue = value / 1000;
    final bool isEnabled = enabled;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Ds.tileShape(index + 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Opacity(
                opacity: isEnabled ? 1 : 0.6,
                child: IconBadge(icon: icon, color: fg, size: 44),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                "${(normalizedValue * 100).toInt()}%",
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 14,
              activeTrackColor: fg,
              inactiveTrackColor: fg.withValues(alpha: 0.2),
              thumbColor: fg,
            ),
            child: Slider(value: normalizedValue, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
