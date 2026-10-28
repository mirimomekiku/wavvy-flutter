import 'dart:math' as math;

/// Number of bars the visualizer draws, and bands the native side produces.
const int kVisualizerBands = 32;

/// Level range the spectrum is mapped from (decibels relative to a byte of
/// 128), and the tilt that lifts the highs, which music has far less of.
/// `VisualizerBridge.kt` uses the same numbers; tune them together.
const double kVisualizerFloorDb = -52;
const double kVisualizerCeilDb = -6;
const double kVisualizerTiltDb = 10;

/// First and last FFT bin the bars cover (bin k is k * sampleRate / size).
const int kVisualizerFirstBin = 2;
const double kVisualizerLastFraction = 0.73;

/// Reference for what the native bridge does to one Visualizer FFT frame:
/// [fft] is the raw byte array (bytes are signed; element 0 is the DC value,
/// element 1 the Nyquist value, then a real and imaginary byte per bin) and the
/// result is [bands] levels in 0..1, log-spaced from low to high.
List<double> fftToBands(List<int> fft, {int bands = kVisualizerBands}) {
  final out = List<double>.filled(bands, 0);
  final bins = fft.length ~/ 2; // complex bins, DC pair included
  if (bins < 4 || bands < 1) return out;
  final lo = kVisualizerFirstBin.toDouble();
  final hi = math.max(lo + bands.toDouble(), bins * kVisualizerLastFraction);
  double edge(int i) => lo * math.pow(hi / lo, i / bands);
  for (var b = 0; b < bands; b++) {
    final start = edge(b).floor().clamp(1, bins - 1);
    final end = math.max(start + 1, edge(b + 1).ceil()).clamp(start + 1, bins);
    var peak = 0.0;
    for (var k = start; k < end; k++) {
      final re = fft[2 * k].toSigned(8).toDouble();
      final im = fft[2 * k + 1].toSigned(8).toDouble();
      peak = math.max(peak, math.sqrt(re * re + im * im));
    }
    final tilt = bands > 1 ? kVisualizerTiltDb * b / (bands - 1) : 0.0;
    out[b] = normalizeMagnitude(peak, tiltDb: tilt);
  }
  return out;
}

/// Maps a bin magnitude (0..~181) to 0..1 on a decibel scale.
double normalizeMagnitude(double magnitude, {double tiltDb = 0}) {
  final db = 20 * math.log(magnitude / 128 + 1e-6) / math.ln10 + tiltDb;
  final t =
      (db - kVisualizerFloorDb) / (kVisualizerCeilDb - kVisualizerFloorDb);
  return t.clamp(0.0, 1.0);
}

/// One smoothing step: a band moves [attack] of the way up to a louder value
/// and [decay] of the way down to a quieter one, so bars jump up and fall back
/// slowly. Both are fractions in 0..1.
List<double> smoothBands(
  List<double> previous,
  List<double> next, {
  double attack = 0.7,
  double decay = 0.2,
}) {
  final out = List<double>.filled(next.length, 0);
  for (var i = 0; i < next.length; i++) {
    final from = i < previous.length ? previous[i] : 0.0;
    final target = next[i].clamp(0.0, 1.0);
    final k = target > from ? attack : decay;
    out[i] = (from + (target - from) * k).clamp(0.0, 1.0);
  }
  return out;
}

/// Peak caps: a cap jumps to a bar that passes it and then falls by [fall] per
/// step, never below the bar itself.
List<double> updatePeaks(
  List<double> peaks,
  List<double> bands, {
  double fall = 0.02,
}) {
  final out = List<double>.filled(bands.length, 0);
  for (var i = 0; i < bands.length; i++) {
    final held = i < peaks.length ? peaks[i] - fall : 0.0;
    out[i] = math.max(bands[i], held).clamp(0.0, 1.0);
  }
  return out;
}

/// A quiet, fixed frame for reduced motion and for "nothing playing".
List<double> stillBands({int bands = kVisualizerBands}) => [
  for (var i = 0; i < bands; i++)
    0.1 + 0.05 * math.sin(i * 0.55) + 0.1 * (1 - i / math.max(1, bands - 1)),
];

/// Largest gap between two frames; the easing stops below this.
double maxBandGap(List<double> a, List<double> b) {
  var gap = 0.0;
  for (var i = 0; i < math.min(a.length, b.length); i++) {
    gap = math.max(gap, (a[i] - b[i]).abs());
  }
  return gap;
}
