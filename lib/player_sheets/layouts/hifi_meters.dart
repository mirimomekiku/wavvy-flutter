import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';

// The analog meters of the Hi-Fi deck. Nothing here knows about the
// visualizer, so the Play build can use it: hifi_live_meters.dart feeds it real
// levels in the full build, and [HifiTimeMeters] is the honest fallback.

/// How far the needle swings either side of straight up.
const double kHifiNeedleSweep = 50 * math.pi / 180;

/// The needle's angle (radians, 0 = pointing right, -pi / 2 = straight up)
/// for a [level] in 0..1.
double hifiNeedleAngle(double level) =>
    -math.pi / 2 + (level.clamp(0.0, 1.0) - 0.5) * 2 * kHifiNeedleSweep;

/// The bass and treble readings from the visualizer's low-to-high [bands]:
/// a mix of the loudest and the average band in the lowest and in the highest
/// quarter. No bands (nothing playing) read as rest.
({double bass, double treble}) hifiBandLevels(List<double> bands) {
  if (bands.isEmpty) return (bass: 0.0, treble: 0.0);
  final n = math.max(1, bands.length ~/ 4);
  double read(Iterable<double> v) {
    var peak = 0.0, sum = 0.0, count = 0;
    for (final x in v) {
      peak = math.max(peak, x);
      sum += x;
      count++;
    }
    return count == 0 ? 0.0 : (0.6 * peak + 0.4 * sum / count).clamp(0.0, 1.0);
  }

  return (
    bass: read(bands.take(n)),
    treble: read(bands.skip(bands.length - n)),
  );
}

/// One step of a damped spring pulling [x] toward [target], in [dt] seconds.
/// The spring is stepped in small slices so a long frame cannot blow it up.
({double x, double v}) hifiSpringStep(
  double x,
  double v,
  double target,
  double dt, {
  double stiffness = 160,
  double damping = 13,
}) {
  var left = math.min(dt, 0.1);
  while (left > 0) {
    final h = math.min(left, 1 / 120);
    v += (stiffness * (target - x) - damping * v) * h;
    x += v * h;
    left -= h;
  }
  return (x: x, v: v);
}

/// An analog needle meter: a scale arc, tick marks, an optional red zone and a
/// needle that follows [level] (0..1) on a spring. With reduced motion the
/// needle jumps. The needle's own animation repaints only the painter.
class HifiMeter extends StatefulWidget {
  const HifiMeter({
    super.key,
    required this.level,
    required this.label,
    required this.semanticsLabel,
    this.semanticsValue,
    this.caption,
    this.redZone = false,
    this.bouncy = true,
  });

  /// Where the needle points, 0..1.
  final double level;

  /// The text under the dial (BASS, TREBLE, ELAPSED...).
  final String label;
  final String semanticsLabel;
  final String? semanticsValue;

  /// A second line under the label, such as the time a gauge reads.
  final String? caption;

  /// Paint the last fifth of the scale red. Only for level meters.
  final bool redZone;

  /// Overshoot a little, like a real moving coil. Gauges do not.
  final bool bouncy;

  @override
  State<HifiMeter> createState() => _HifiMeterState();
}

class _HifiMeterState extends State<HifiMeter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final ValueNotifier<double> _shown = ValueNotifier(widget.level);
  double _velocity = 0;
  Duration _last = Duration.zero;
  bool _still = false;

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final next = hifiSpringStep(
      _shown.value,
      _velocity,
      widget.level,
      dt,
      damping: widget.bouncy ? 13 : 2 * math.sqrt(160),
    );
    _velocity = next.v;
    _shown.value = next.x;
    if ((widget.level - next.x).abs() < 0.0008 && next.v.abs() < 0.004) {
      _shown.value = widget.level;
      _velocity = 0;
      _ticker.stop();
    }
  }

  void _retarget() {
    if (_still) {
      _velocity = 0;
      if (_ticker.isActive) _ticker.stop();
      _shown.value = widget.level;
    } else if (!_ticker.isActive && _shown.value != widget.level) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _retarget();
  }

  @override
  void didUpdateWidget(HifiMeter old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) _retarget();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Semantics(
      label: widget.semanticsLabel,
      value: widget.semanticsValue,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1.7,
            child: DecoratedBox(
              decoration: a.lcdDecoration.copyWith(
                borderRadius: BorderRadius.circular(8),
              ),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: HifiMeterPainter(a, _shown, redZone: widget.redZone),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: a.textSecondary,
              ),
            ),
          ),
          if (widget.caption != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.caption!,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: a.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the dial; repaints when the needle's level moves.
class HifiMeterPainter extends CustomPainter {
  HifiMeterPainter(this.a, this.shown, {this.redZone = false})
    : super(repaint: shown);
  final WvPalette a;
  final ValueListenable<double> shown;
  final bool redZone;

  /// The level the needle is drawn at right now.
  double get level => shown.value;

  static const _red = Color(0xFFD8453B);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final pivot = Offset(size.width / 2, size.height * 0.9);
    final r = math.min(size.width * 0.46, size.height * 0.74);
    final inkColor = a.text.withValues(alpha: 0.78);
    final from = hifiNeedleAngle(0);
    final sweep = kHifiNeedleSweep * 2;
    final arc = Rect.fromCircle(center: pivot, radius: r);
    final stroke = math.max(1.2, r / 40);

    // Scale arc, with the red zone over the last fifth.
    final cut = redZone ? 0.8 : 1.0;
    canvas.drawArc(
      arc,
      from,
      sweep * cut,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = inkColor,
    );
    if (redZone) {
      canvas.drawArc(
        arc,
        from + sweep * cut,
        sweep * (1 - cut),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 2.2
          ..color = _red,
      );
    }
    // Ticks: a long one every fifth, short ones between.
    for (var i = 0; i <= 20; i++) {
      final t = i / 20;
      final major = i % 4 == 0;
      final angle = from + sweep * t;
      final dir = Offset(math.cos(angle), math.sin(angle));
      final inner = r - (major ? r * 0.16 : r * 0.08);
      canvas.drawLine(
        pivot + dir * inner,
        pivot + dir * r,
        Paint()
          ..strokeWidth = major ? stroke * 1.3 : stroke * 0.8
          ..color = redZone && t > cut - 1e-6 ? _red : inkColor,
      );
    }
    // The needle, with a soft shadow, and its hub.
    final angle = hifiNeedleAngle(level);
    final tip = pivot + Offset(math.cos(angle), math.sin(angle)) * (r * 0.97);
    canvas.drawLine(
      pivot + const Offset(0.8, 1.2),
      tip + const Offset(0.8, 1.2),
      Paint()
        ..strokeWidth = stroke * 1.5
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.22),
    );
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..strokeWidth = stroke * 1.5
        ..strokeCap = StrokeCap.round
        ..color = a.dark ? const Color(0xFFFFB347) : const Color(0xFF9A2B20),
    );
    canvas.drawCircle(pivot, r * 0.07, Paint()..color = inkColor);
  }

  @override
  bool shouldRepaint(HifiMeterPainter old) =>
      old.a != a || old.redZone != redZone || old.shown != shown;
}

/// Two gauges for when live levels are not available: the time played and
/// the time left, drawn like the level meters but never pretending to be one.
class HifiTimeMeters extends ConsumerWidget {
  const HifiTimeMeters({super.key, this.gap = 10});
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);
    final total = duration.inMilliseconds;
    final played = total > 0
        ? (position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;
    final left = duration > position ? duration - position : Duration.zero;
    final elapsed = PlayerUtils.formatDuration(position);
    final remaining = PlayerUtils.formatDuration(left);
    return Row(
      children: [
        Expanded(
          child: HifiMeter(
            level: played,
            bouncy: false,
            label: 'ELAPSED',
            caption: elapsed,
            semanticsLabel: 'Time elapsed',
            semanticsValue: elapsed,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: HifiMeter(
            level: total > 0 ? 1 - played : 0,
            bouncy: false,
            label: 'REMAINING',
            caption: remaining,
            semanticsLabel: 'Time remaining',
            semanticsValue: remaining,
          ),
        ),
      ],
    );
  }
}
