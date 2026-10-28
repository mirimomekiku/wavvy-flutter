import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

// A seven-segment readout for the CD player layout, painted from paths (no
// font). Digits 0-9, a dash, a colon and a slash; lit segments sit over a dim
// "8" like a real LCD.

/// The bits of a segment mask. The segments are named as on any seven-segment
/// part: a on top, then b, c down the right, d at the bottom, e, f up the left
/// and g across the middle.
const int kSegA = 1;
const int kSegB = 2;
const int kSegC = 4;
const int kSegD = 8;
const int kSegE = 16;
const int kSegF = 32;
const int kSegG = 64;

const List<int> _digitMasks = [
  kSegA | kSegB | kSegC | kSegD | kSegE | kSegF, // 0
  kSegB | kSegC, // 1
  kSegA | kSegB | kSegD | kSegE | kSegG, // 2
  kSegA | kSegB | kSegC | kSegD | kSegG, // 3
  kSegB | kSegC | kSegF | kSegG, // 4
  kSegA | kSegC | kSegD | kSegF | kSegG, // 5
  kSegA | kSegC | kSegD | kSegE | kSegF | kSegG, // 6
  kSegA | kSegB | kSegC, // 7
  kSegA | kSegB | kSegC | kSegD | kSegE | kSegF | kSegG, // 8
  kSegA | kSegB | kSegC | kSegD | kSegF | kSegG, // 9
];

/// Which segments light for [ch]: a digit, or a dash (just g). Anything else,
/// the colon and the slash included, has no segments (they are drawn on their
/// own).
int cdSegmentMask(String ch) {
  if (ch.length != 1) return 0;
  final code = ch.codeUnitAt(0);
  if (code >= 0x30 && code <= 0x39) return _digitMasks[code - 0x30];
  if (ch == '-') return kSegG;
  return 0;
}

/// A song position as the display shows it: mm:ss, or h:mm:ss from an hour.
String cdTimeText(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total ~/ 60) % 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// "03/12": the track number out of the queue's length. [index] counts from
/// zero, as the player's current index does; dashes when nothing is loaded.
String cdTrackText(int index, int total) {
  if (index < 0 || total <= 0) return '--/--';
  final digits = total.toString().length < 2 ? 2 : total.toString().length;
  String pad(int v) => v.toString().padLeft(digits, '0');
  return '${pad(index + 1)}/${pad(total)}';
}

/// The color of a lit segment: the accent, pushed away from the LCD's
/// background so it reads on the pale light display and the dark one.
Color cdLitColor(WvPalette a) => a.dark
    ? Color.lerp(a.accent, Colors.white, 0.3)!
    : Color.lerp(a.accent, Colors.black, 0.45)!;

/// The color of an unlit segment, a faint trace of [lit].
Color cdDimColor(Color lit) => lit.withValues(alpha: 0.13);

double _cell(String ch, double h) => switch (ch) {
  ':' => h * 0.2,
  '/' => h * 0.38,
  ' ' => h * 0.3,
  _ => h * 0.56,
};

/// How wide [text] is when drawn [height] tall (the lean included).
double cdSegmentWidth(String text, double height) {
  if (text.isEmpty) return 0;
  var w = 0.0;
  for (final ch in text.characters) {
    w += _cell(ch, height);
  }
  return w + height * 0.14 * (text.characters.length - 1) + height * 0.12;
}

Path _hex(Offset c, double len, double t, {required bool horizontal}) {
  final h = len / 2;
  final k = t / 2;
  final pts = horizontal
      ? [
          Offset(c.dx - h, c.dy),
          Offset(c.dx - h + k, c.dy - k),
          Offset(c.dx + h - k, c.dy - k),
          Offset(c.dx + h, c.dy),
          Offset(c.dx + h - k, c.dy + k),
          Offset(c.dx - h + k, c.dy + k),
        ]
      : [
          Offset(c.dx, c.dy - h),
          Offset(c.dx + k, c.dy - h + k),
          Offset(c.dx + k, c.dy + h - k),
          Offset(c.dx, c.dy + h),
          Offset(c.dx - k, c.dy + h - k),
          Offset(c.dx - k, c.dy - h + k),
        ];
  return Path()..addPolygon(pts, true);
}

/// The seven segment shapes of one digit cell, in a to g order.
List<Path> _segments(double w, double h) {
  final t = h * 0.13;
  final g = t * 0.14;
  final hLen = w - t - 2 * g;
  final vLen = h / 2 - t / 2 - 2 * g;
  return [
    _hex(Offset(w / 2, t / 2), hLen, t, horizontal: true), // a
    _hex(Offset(w - t / 2, h / 4 + t / 4), vLen, t, horizontal: false), // b
    _hex(Offset(w - t / 2, 3 * h / 4 - t / 4), vLen, t, horizontal: false), // c
    _hex(Offset(w / 2, h - t / 2), hLen, t, horizontal: true), // d
    _hex(Offset(t / 2, 3 * h / 4 - t / 4), vLen, t, horizontal: false), // e
    _hex(Offset(t / 2, h / 4 + t / 4), vLen, t, horizontal: false), // f
    _hex(Offset(w / 2, h / 2), hLen, t, horizontal: true), // g
  ];
}

/// Draws [text] with its top left at [origin], [height] tall, leaning a little
/// like a real display. Used by the widget below and by the picker thumbnail.
void paintCdSegments(
  Canvas canvas,
  String text,
  Offset origin,
  double height, {
  required Color lit,
  required Color dim,
}) {
  final litPaint = Paint()..color = lit;
  final dimPaint = Paint()..color = dim;
  final t = height * 0.13;
  canvas.save();
  canvas.translate(origin.dx, origin.dy + height);
  canvas.skew(-0.12, 0);
  canvas.translate(0, -height);
  var x = 0.0;
  for (final ch in text.characters) {
    final w = _cell(ch, height);
    canvas.save();
    canvas.translate(x, 0);
    switch (ch) {
      case ':':
        for (final f in const [0.32, 0.68]) {
          canvas.drawCircle(Offset(w / 2, height * f), t * 0.6, litPaint);
        }
      case '/':
        canvas.drawLine(
          Offset(w, height * 0.08),
          Offset(0, height * 0.92),
          litPaint
            ..strokeWidth = t * 0.7
            ..strokeCap = StrokeCap.round,
        );
      case ' ':
        break;
      default:
        final mask = cdSegmentMask(ch);
        final shapes = _segments(w, height);
        for (var i = 0; i < 7; i++) {
          canvas.drawPath(
            shapes[i],
            mask & (1 << i) != 0 ? litPaint : dimPaint,
          );
        }
    }
    canvas.restore();
    x += w + height * 0.14;
  }
  canvas.restore();
}

/// [text] as lit segments over dim ones, [height] tall.
class CdSegmentText extends StatelessWidget {
  const CdSegmentText({
    super.key,
    required this.text,
    required this.height,
    required this.lit,
    required this.dim,
  });
  final String text;
  final double height;
  final Color lit;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(cdSegmentWidth(text, height), height),
      painter: _SegmentPainter(text, height, lit, dim),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  _SegmentPainter(this.text, this.height, this.lit, this.dim);
  final String text;
  final double height;
  final Color lit;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) =>
      paintCdSegments(canvas, text, Offset.zero, height, lit: lit, dim: dim);

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.text != text ||
      old.height != height ||
      old.lit != lit ||
      old.dim != dim;
}
