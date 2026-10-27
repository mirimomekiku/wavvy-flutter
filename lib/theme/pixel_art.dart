import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Procedural pixel-art kit: sprites, generated covers, equalizer, loader,
/// segmented progress, stepped corners, a pixel-font kicker and the Material 3
/// expressive wavy slider. Everything is drawn with [CustomPainter]s on
/// integer-aligned rectangles and colored from the theme palette.

double _fin(double v, [double fallback = 0]) => v.isFinite ? v : fallback;

// ------------------------------------------------------------------ Sprites

/// A grid of cells. Rows are equal-length strings; ' ' and '.' are transparent,
/// any other char is a cell colored by [PixelSpriteView].
class PixelSprite {
  const PixelSprite(this.rows);
  final List<String> rows;

  int get height => rows.length;
  int get width => rows.isEmpty ? 0 : rows.first.length;
}

/// Ready-made sprites. In multi-color (themed) sprites the chars are:
/// o outline, a accent, b primaryContainer, c tertiary, d tertiaryContainer,
/// s secondaryContainer, w highlight, k dark eye.
abstract final class PixelSprites {
  static const PixelSprite note = PixelSprite([
    '............',
    '..########..',
    '..########..',
    '..##....##..',
    '..##....##..',
    '..##....##..',
    '..##....##..',
    '.###...###..',
    '####..####..',
    '####..####..',
    '.##....##...',
    '............',
  ]);

  static const PixelSprite vinyl = PixelSprite([
    '...######...',
    '..########..',
    '.##########.',
    '####....####',
    '####.##.####',
    '###.####.###',
    '###.####.###',
    '####.##.####',
    '####....####',
    '.##########.',
    '..########..',
    '...######...',
  ]);

  static const PixelSprite headphones = PixelSprite([
    '...######...',
    '..##....##..',
    '.##......##.',
    '.#........#.',
    '##........##',
    '##........##',
    '####....####',
    '####....####',
    '####....####',
    '####....####',
    '.##......##.',
    '............',
  ]);

  static const PixelSprite cassette = PixelSprite([
    '............',
    '############',
    '#..........#',
    '#.########.#',
    '#.#..##..#.#',
    '#.#..##..#.#',
    '#.########.#',
    '#..........#',
    '#..######..#',
    '#.#......#.#',
    '############',
    '............',
  ]);

  static const PixelSprite speaker = PixelSprite([
    '............',
    '......#.....',
    '.....##..#..',
    '....###...#.',
    '####.##.#..#',
    '####.##..#.#',
    '####.##..#.#',
    '####.##.#..#',
    '....###...#.',
    '.....##..#..',
    '......#.....',
    '............',
  ]);

  static const PixelSprite heart = PixelSprite([
    '............',
    '.####..####.',
    '############',
    '############',
    '############',
    '.##########.',
    '..########..',
    '...######...',
    '....####....',
    '.....##.....',
    '............',
    '............',
  ]);

  static const PixelSprite star = PixelSprite([
    '.....##.....',
    '.....##.....',
    '....####....',
    '############',
    '.##########.',
    '..########..',
    '..########..',
    '.####..####.',
    '.###....###.',
    '.#........#.',
    '............',
    '............',
  ]);

  static const PixelSprite search = PixelSprite([
    '..#####.....',
    '.##...##....',
    '##.....##...',
    '#.......#...',
    '#.......#...',
    '##.....##...',
    '.##...##....',
    '..#####.##..',
    '........###.',
    '.........###',
    '..........##',
    '............',
  ]);

  static const PixelSprite download = PixelSprite([
    '....####....',
    '....####....',
    '....####....',
    '..########..',
    '...######...',
    '....####....',
    '.....##.....',
    '............',
    '#..........#',
    '############',
    '............',
    '............',
  ]);

  static const PixelSprite home = PixelSprite([
    '.....##.....',
    '....####....',
    '...######...',
    '..########..',
    '.##########.',
    '############',
    '.####..####.',
    '.####..####.',
    '.####..####.',
    '.####..####.',
    '............',
    '............',
  ]);

  static const PixelSprite library = PixelSprite([
    '....###.....',
    '###.###.####',
    '###.###.####',
    '#.#.#.#.#..#',
    '###.###.####',
    '###.###.####',
    '###.###.####',
    '###.###.####',
    '############',
    '############',
    '............',
    '............',
  ]);

  /// "Wavvy": a friendly blob with headphones.
  static const PixelSprite mascot = PixelSprite([
    '....aaaaaaaa....',
    '..aaaaaaaaaaaa..',
    '.aa..oooooo..aa.',
    '.a..oobbbboo..a.',
    '.a.obbbbbbbbo.a.',
    'ccobbbbbbbbbbocc',
    'ccobbkwbbwkbbocc',
    'ccobbkkbbkkbbocc',
    'ccobbkkbbkkbbocc',
    'ccobsbobbobsbocc',
    '..obbbboobbbbo..',
    '...oobbbbbboo...',
    '....oooooooo....',
    '....odd..ddo....',
    '....ooo..ooo....',
    '................',
  ]);

  /// Wavvy with happy, closed eyes.
  static const PixelSprite mascotHappy = PixelSprite([
    '....aaaaaaaa....',
    '..aaaaaaaaaaaa..',
    '.aa..oooooo..aa.',
    '.a..oobbbboo..a.',
    '.a.obbbbbbbbo.a.',
    'ccobbbbbbbbbbocc',
    'ccobbkbbbbkbbocc',
    'ccobkbkbbkbkbocc',
    'ccobbbbbbbbbbocc',
    'ccobsbobbobsbocc',
    '..obbbboobbbbo..',
    '...oobbbbbboo...',
    '....oooooooo....',
    '....odd..ddo....',
    '....ooo..ooo....',
    '................',
  ]);

  /// Wavvy, sleepy.
  static const PixelSprite mascotSleepy = PixelSprite([
    '....aaaaaaaa....',
    '..aaaaaaaaaaaa..',
    '.aa..oooooo..aa.',
    '.a..oobbbboo..a.',
    '.a.obbbbbbbbo.a.',
    'ccobbbbbbbbbbocc',
    'ccobbbbbbbbbbocc',
    'ccobkkkbbkkkbocc',
    'ccobbbbbbbbbbocc',
    'ccobsbbbbbbsbocc',
    '..obbbboobbbbo..',
    '...oobbbbbboo...',
    '....oooooooo....',
    '....odd..ddo....',
    '....ooo..ooo....',
    '................',
  ]);
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.sprite, this.colors, this.single);
  final PixelSprite sprite;
  final Map<String, Color> colors;
  final Color? single;

  @override
  void paint(Canvas canvas, Size size) {
    final w = sprite.width, h = sprite.height;
    if (w == 0 || h == 0 || size.isEmpty) return;
    var cell = math.min(size.width / w, size.height / h);
    if (cell >= 1) cell = cell.floorToDouble();
    final ox = ((size.width - cell * w) / 2).roundToDouble();
    final oy = ((size.height - cell * h) / 2).roundToDouble();
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < h; y++) {
      final row = sprite.rows[y];
      var x = 0;
      while (x < row.length) {
        final ch = row[x];
        if (ch == ' ' || ch == '.') {
          x++;
          continue;
        }
        var end = x + 1;
        while (end < row.length && row[end] == ch) {
          end++;
        }
        final color = single ?? colors[ch];
        if (color != null) {
          paint.color = color;
          canvas.drawRect(
            Rect.fromLTWH(ox + x * cell, oy + y * cell, (end - x) * cell, cell),
            paint,
          );
        }
        x = end;
      }
    }
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.sprite != sprite ||
      old.single != single ||
      !mapEquals(old.colors, colors);
}

class PixelSpriteView extends StatelessWidget {
  const PixelSpriteView({
    super.key,
    required this.sprite,
    required this.size,
    this.color,
    this.themed = false,
  });

  final PixelSprite sprite;

  /// Rendered height in logical px; width follows the sprite aspect ratio.
  final double size;
  final Color? color;
  final bool themed;

  @override
  Widget build(BuildContext context) {
    final p = Wv.of(context);
    final h = math.max(0.0, _fin(size));
    final w = sprite.height == 0 ? 0.0 : h * sprite.width / sprite.height;
    final Map<String, Color> colors = themed
        ? {
            'o': p.text,
            'a': p.accent,
            'b': p.primaryContainer,
            'c': p.tertiary,
            'd': p.tertiaryContainer,
            's': p.secondaryContainer,
            'w': p.onPrimaryContainer.withValues(alpha: 0.9),
            'k': p.background,
          }
        : const {};
    return RepaintBoundary(
      child: SizedBox(
        width: w,
        height: h,
        child: CustomPaint(
          painter: _SpritePainter(
            sprite,
            colors,
            themed ? null : (color ?? p.text),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- Cover

int _mix(int x) {
  x = (x ^ 0x9E3779B9) & 0xFFFFFFFF;
  x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
  x = ((x ^ (x >> 16)) * 0x45D9F3B) & 0xFFFFFFFF;
  return (x ^ (x >> 16)) & 0xFFFFFFFF;
}

/// Mirrored 8x8 pattern, deterministic from [seed]. Never empty.
@visibleForTesting
List<List<bool>> pixelCoverPattern(int seed) {
  var s = _mix(seed & 0xFFFFFFFF);
  var s2 = _mix(s + 0x7F4A7C15);
  final grid = List.generate(8, (_) => List.filled(8, false));
  var any = false;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 4; x++) {
      final bit = y * 4 + x;
      final src = bit < 16 ? s : s2;
      final on =
          ((src >> (bit % 16)) & 1) == 1 || ((src >> (bit % 16 + 7)) & 3) == 3;
      grid[y][x] = on;
      grid[y][7 - x] = on;
      any = any || on;
    }
  }
  if (!any) {
    grid[3][3] = grid[3][4] = grid[4][3] = grid[4][4] = true;
  }
  return grid;
}

/// (background, foreground) tonal pair for a cover, deterministic from [seed].
@visibleForTesting
///
/// With a [base] color (the theme's primary) the cover's hue is the base hue
/// rotated by a curated offset (analogous / triadic steps), so covers stay
/// varied but always harmonize with the current Material You / album palette.
/// Without one, the hue is free-running (used by tests).
(Color, Color) pixelCoverColors(int seed, {bool dark = true, Color? base}) {
  final h = _mix((seed & 0xFFFFFFFF) + 0x1234567);
  double hue;
  if (base != null) {
    const offsets = [0, 28, 60, 150, 180, 210, 300, 332];
    hue = (HSLColor.fromColor(base).hue + offsets[h % offsets.length]) % 360;
  } else {
    hue = (h % 360).toDouble();
  }
  final hue2 = (hue + 25 + (h >> 9) % 50) % 360;
  final bg = HSLColor.fromAHSL(1, hue, 0.4, dark ? 0.24 : 0.84).toColor();
  final fg = HSLColor.fromAHSL(1, hue2, 0.55, dark ? 0.66 : 0.38).toColor();
  return (bg, fg);
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.pattern, this.bg, this.fg);
  final List<List<bool>> pattern;
  final Color bg, fg;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, paint..color = bg);
    paint.color = fg;
    final cw = size.width / 8, ch = size.height / 8;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        if (!pattern[y][x]) continue;
        canvas.drawRect(
          Rect.fromLTRB(
            (x * cw).roundToDouble(),
            (y * ch).roundToDouble(),
            ((x + 1) * cw).roundToDouble(),
            ((y + 1) * ch).roundToDouble(),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CoverPainter old) =>
      old.bg != bg || old.fg != fg || old.pattern != pattern;
}

/// Procedural cover art for songs/albums without artwork.
class WvPixelCover extends StatelessWidget {
  const WvPixelCover({
    super.key,
    required this.seed,
    this.size,
    this.radius = 0,
  });

  final int seed;
  final double? size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = Wv.of(context);
    final pattern = pixelCoverPattern(seed);
    final (bg, fg) = pixelCoverColors(
      seed,
      dark: palette.dark,
      base: palette.accent,
    );
    Widget art = CustomPaint(
      painter: _CoverPainter(pattern, bg, fg),
      child: const SizedBox.expand(),
    );
    if (radius > 0) {
      art = ClipRRect(borderRadius: BorderRadius.circular(radius), child: art);
    }
    final s = size;
    if (s != null) {
      return SizedBox(
        width: math.max(0, _fin(s)),
        height: math.max(0, _fin(s)),
        child: art,
      );
    }
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        width: c.hasBoundedWidth ? c.maxWidth : 48,
        height: c.hasBoundedHeight ? c.maxHeight : 48,
        child: art,
      ),
    );
  }
}

// ---------------------------------------------------------------- Equalizer

class _EqPainter extends CustomPainter {
  _EqPainter(this.controller, this.color, this.animate)
    : super(repaint: animate ? controller : null);
  final Animation<double> controller;
  final Color color;
  final bool animate;

  static const _static = [3, 5, 2, 4];
  static const _speed = [1.0, 1.7, 1.3, 2.1];
  static const _phase = [0.0, 1.1, 2.3, 3.7];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const rows = 7;
    final cell = math.max(
      1.0,
      (math.min(size.width / 7, size.height / rows)).floorToDouble(),
    );
    final totalW = cell * 7;
    final totalH = cell * rows;
    final ox = ((size.width - totalW) / 2).roundToDouble();
    final oy = ((size.height - totalH) / 2).roundToDouble();
    final t = animate ? (controller.value * 14).floor() / 14 : 0.0;
    final paint = Paint()
      ..isAntiAlias = false
      ..color = color;
    for (var i = 0; i < 4; i++) {
      final n = animate
          ? (((math.sin(2 * math.pi * t * _speed[i] * 2 + _phase[i]) + 1) / 2) *
                        (rows - 1))
                    .round() +
                1
          : _static[i];
      for (var b = 0; b < n; b++) {
        canvas.drawRect(
          Rect.fromLTWH(
            ox + i * 2 * cell,
            oy + totalH - (b + 1) * cell,
            cell,
            cell,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) =>
      old.color != color ||
      old.animate != animate ||
      old.controller != controller;
}

/// Animated pixel equalizer: 4 bars of square blocks bouncing in steps.
class PixelEqualizer extends StatefulWidget {
  const PixelEqualizer({
    super.key,
    this.size = 18,
    this.color,
    this.animate = true,
  });
  final double size;
  final Color? color;
  final bool animate;

  @override
  State<PixelEqualizer> createState() => _PixelEqualizerState();
}

class _PixelEqualizerState extends State<PixelEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(PixelEqualizer old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = math.max(0.0, _fin(widget.size));
    return RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: CustomPaint(
          painter: _EqPainter(
            _c,
            widget.color ?? Wv.of(context).accentText,
            widget.animate,
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- Progress

class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.value, this.blocks, this.color, this.track);
  final double value;
  final int blocks;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final gap = size.width / blocks > 6 ? 2.0 : 1.0;
    final cw = (size.width - gap * (blocks - 1)) / blocks;
    if (cw <= 0) return;
    final filled = (value * blocks).round();
    final paint = Paint()..isAntiAlias = false;
    for (var i = 0; i < blocks; i++) {
      final l = (i * (cw + gap)).roundToDouble();
      final r = (i * (cw + gap) + cw).roundToDouble();
      if (r <= l) continue;
      canvas.drawRect(
        Rect.fromLTRB(l, 0, r, size.height),
        paint..color = i < filled ? color : track,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.value != value ||
      old.blocks != blocks ||
      old.color != color ||
      old.track != track;
}

/// Segmented block progress bar.
class PixelProgress extends StatelessWidget {
  const PixelProgress({
    super.key,
    required this.value,
    this.blocks = 28,
    this.height = 6,
    this.color,
    this.trackColor,
  });

  final double value;
  final int blocks;
  final double height;
  final Color? color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final p = Wv.of(context);
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final n = blocks < 1 ? 1 : blocks;
    final h = math.max(0.0, _fin(height));
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, c) => SizedBox(
          width: c.hasBoundedWidth ? c.maxWidth : 120,
          height: h,
          child: CustomPaint(
            painter: _ProgressPainter(
              v,
              n,
              color ?? p.accent,
              trackColor ?? p.surfaceHighest,
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Corners

/// Rectangle with stepped ("pixel") corners.
class PixelCornersBorder extends ShapeBorder {
  const PixelCornersBorder({
    this.step = 4,
    this.steps = 2,
    this.side = BorderSide.none,
  });

  final double step;
  final int steps;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _path(Rect rect) {
    final w = rect.width, h = rect.height;
    if (w <= 0 || h <= 0) return Path()..addRect(rect);
    final s = step > 0 ? step : 0.0;
    var n = steps;
    if (s > 0) {
      n = math.min(n, (math.min(w, h) / 2 / s).floor());
    }
    if (n <= 0 || s <= 0) return Path()..addRect(rect);
    // Staircase from (0, n*s) to (n*s, 0).
    final seq = <Offset>[Offset(0, n * s)];
    for (var i = 0; i < n; i++) {
      seq.add(Offset((i + 1) * s, (n - i) * s));
      seq.add(Offset((i + 1) * s, (n - i - 1) * s));
    }
    final path = Path();
    Offset tl(Offset o) => Offset(rect.left + o.dx, rect.top + o.dy);
    Offset tr(Offset o) => Offset(rect.right - o.dx, rect.top + o.dy);
    Offset br(Offset o) => Offset(rect.right - o.dx, rect.bottom - o.dy);
    Offset bl(Offset o) => Offset(rect.left + o.dx, rect.bottom - o.dy);
    path.moveTo(tl(seq.first).dx, tl(seq.first).dy);
    for (final o in seq.skip(1)) {
      final p = tl(o);
      path.lineTo(p.dx, p.dy);
    }
    for (final o in seq.reversed) {
      final p = tr(o);
      path.lineTo(p.dx, p.dy);
    }
    for (final o in seq) {
      final p = br(o);
      path.lineTo(p.dx, p.dy);
    }
    for (final o in seq.reversed) {
      final p = bl(o);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side.width
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = false
      ..color = side.color;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), paint);
  }

  @override
  ShapeBorder scale(double t) =>
      PixelCornersBorder(step: step * t, steps: steps, side: side.scale(t));

  @override
  bool operator ==(Object other) =>
      other is PixelCornersBorder &&
      other.step == step &&
      other.steps == steps &&
      other.side == side;

  @override
  int get hashCode => Object.hash(step, steps, side);
}

// ------------------------------------------------------------- Pixel typeface

/// Offline monospace labels complement the procedural pixel artwork.
TextStyle wvPixelTextStyle({
  double size = 10,
  Color? color,
  double letterSpacing = 0.8,
}) {
  return TextStyle(
    fontFamily: 'WorkSans',
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: letterSpacing,
    height: 1.2,
  );
}

/// Tiny pixel-font label (all caps, letter-spaced).
class WvKicker extends StatelessWidget {
  const WvKicker(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: wvPixelTextStyle(color: color ?? Wv.of(context).accentText),
  );
}

// ------------------------------------------------------------------- Loader

class _LoaderPainter extends CustomPainter {
  _LoaderPainter(this.controller, this.color) : super(repaint: controller);
  final Animation<double> controller;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    if (s <= 0) return;
    final cell = math.max(1.0, (s * 0.4).floorToDouble());
    final gap = math.max(
      0.0,
      math.min((s - 2 * cell).floorToDouble(), (s * 0.2).floorToDouble()),
    );
    final total = 2 * cell + gap;
    final ox = ((size.width - total) / 2).roundToDouble();
    final oy = ((size.height - total) / 2).roundToDouble();
    final active = (controller.value * 4).floor() % 4;
    const order = [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];
    final paint = Paint()..isAntiAlias = false;
    for (var i = 0; i < 4; i++) {
      final age = (active - i + 4) % 4;
      final a = age == 0 ? 1.0 : (age == 1 ? 0.55 : 0.22);
      paint.color = color.withValues(alpha: a);
      canvas.drawRect(
        Rect.fromLTWH(
          ox + order[i].dx * (cell + gap),
          oy + order[i].dy * (cell + gap),
          cell,
          cell,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LoaderPainter old) =>
      old.color != color || old.controller != controller;
}

/// 4-block pixel spinner.
class PixelLoader extends StatefulWidget {
  const PixelLoader({super.key, this.size = 28, this.color});
  final double size;
  final Color? color;

  @override
  State<PixelLoader> createState() => _PixelLoaderState();
}

class _PixelLoaderState extends State<PixelLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = math.max(0.0, _fin(widget.size));
    return RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: CustomPaint(
          painter: _LoaderPainter(
            _c,
            widget.color ?? Wv.of(context).accentText,
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- Wavy slider

class _WavyPainter extends CustomPainter {
  _WavyPainter({
    required this.fraction,
    required this.active,
    required this.inactive,
    required this.phase,
    required this.animate,
  }) : super(repaint: animate ? phase : null);

  final double fraction;
  final Color active, inactive;
  final Animation<double> phase;
  final bool animate;

  static const _inset = 6.0;
  static const _thickness = 5.0;
  static const _amp = 3.5;
  static const _wavelength = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 2 * _inset) return;
    final cy = size.height / 2;
    final x0 = _inset, x1 = size.width - _inset;
    final tx = x0 + (x1 - x0) * fraction;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _thickness
      ..strokeCap = StrokeCap.round;

    if (tx < x1) {
      canvas.drawLine(
        Offset(tx + 4, cy),
        Offset(x1, cy),
        stroke..color = inactive,
      );
    }
    final ph = animate ? phase.value * 2 * math.pi : 0.0;
    final path = Path()..moveTo(x0, cy);
    final len = tx - x0;
    if (len > 0) {
      for (var x = 0.0; x <= len; x += 2) {
        // Ease the amplitude in over the first wavelength so the start is calm.
        final env = math.min(1.0, x / _wavelength);
        path.lineTo(
          x0 + x,
          cy + _amp * env * math.sin(2 * math.pi * x / _wavelength - ph),
        );
      }
      path.lineTo(
        tx,
        cy + _amp * math.sin(2 * math.pi * len / _wavelength - ph),
      );
    } else {
      path.lineTo(x0, cy);
    }
    canvas.drawPath(path, stroke..color = active);

    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(tx, cy), width: 4, height: 22),
      const Radius.circular(2),
    );
    canvas.drawRRect(thumb, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_WavyPainter old) =>
      old.fraction != fraction ||
      old.active != active ||
      old.inactive != inactive ||
      old.animate != animate ||
      old.phase != phase;
}

/// Material 3 expressive wavy seek bar.
class WvWavySlider extends StatefulWidget {
  const WvWavySlider({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.activeColor,
    this.inactiveColor,
    this.animate = true,
  });

  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final Color? activeColor;
  final Color? inactiveColor;
  final bool animate;

  @override
  State<WvWavySlider> createState() => _WvWavySliderState();
}

class _WvWavySliderState extends State<WvWavySlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  double _width = 0;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(WvWavySlider old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _max => widget.max.isFinite && widget.max > 0 ? widget.max : 0;

  double _clamp(double v) => v.isNaN ? 0 : v.clamp(0.0, _max);

  double _fromDx(double dx) {
    const inset = _WavyPainter._inset;
    final span = _width - 2 * inset;
    if (span <= 0 || _max <= 0) return 0;
    return _clamp((dx - inset) / span * _max);
  }

  void _set(double dx) {
    if (_max <= 0) return;
    _last = _fromDx(dx);
    widget.onChanged(_last);
  }

  void _step(double delta) {
    if (_max <= 0) return;
    final v = _clamp(_clamp(widget.value) + delta);
    widget.onChanged(v);
    widget.onChangeEnd?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final p = Wv.of(context);
    final max = _max;
    final value = _clamp(widget.value);
    final fraction = max <= 0 ? 0.0 : value / max;
    final stepSize = max / 20;
    final pct = (fraction * 100).round();

    return Semantics(
      slider: true,
      value: '$pct%',
      increasedValue:
          '${(((value + stepSize) / (max <= 0 ? 1 : max)).clamp(0.0, 1.0) * 100).round()}%',
      decreasedValue:
          '${(((value - stepSize) / (max <= 0 ? 1 : max)).clamp(0.0, 1.0) * 100).round()}%',
      onIncrease: max <= 0 ? null : () => _step(stepSize),
      onDecrease: max <= 0 ? null : () => _step(-stepSize),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, c) {
            _width = c.hasBoundedWidth ? c.maxWidth : 200;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                _set(d.localPosition.dx);
                widget.onChangeEnd?.call(_last);
              },
              onHorizontalDragStart: (d) => _set(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => _set(d.localPosition.dx),
              onHorizontalDragEnd: (_) {
                if (_max > 0) widget.onChangeEnd?.call(_last);
              },
              child: SizedBox(
                width: _width,
                height: 48,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _WavyPainter(
                      fraction: fraction,
                      active: widget.activeColor ?? p.accent,
                      inactive: widget.inactiveColor ?? p.surfaceHighest,
                      phase: _c,
                      animate: widget.animate,
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

/// Quiet, scalable artwork for tracks without embedded cover art.
class WvMediaPlaceholder extends StatelessWidget {
  const WvMediaPlaceholder({
    super.key,
    required this.seed,
    this.size,
    this.radius = 0,
  });
  final int seed;
  final double? size;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    Widget art = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a.surfaceHighest, a.primaryContainer],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, c) => Center(
          child: Icon(
            Icons.album_outlined,
            size: (c.biggest.shortestSide * 0.42).clamp(12.0, 96.0),
            color: a.accent.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
    if (size != null) {
      return SizedBox.square(dimension: math.max(0, _fin(size!)), child: art);
    }
    return art;
  }
}

/// Shared symbols replace decorative sprites throughout the mobile interface.
class WvSymbol extends StatelessWidget {
  const WvSymbol({
    super.key,
    required this.sprite,
    required this.size,
    this.color,
    this.themed = false,
  });
  final PixelSprite sprite;
  final double size;
  final Color? color;
  final bool themed;
  @override
  Widget build(BuildContext context) {
    final icon = identical(sprite, PixelSprites.vinyl)
        ? Icons.album_outlined
        : identical(sprite, PixelSprites.download)
        ? Icons.download_rounded
        : identical(sprite, PixelSprites.search)
        ? Icons.search_rounded
        : identical(sprite, PixelSprites.heart)
        ? Icons.favorite_border_rounded
        : identical(sprite, PixelSprites.cassette)
        ? Icons.library_music_outlined
        : identical(sprite, PixelSprites.note)
        ? Icons.music_note_rounded
        : Icons.headphones_rounded;
    return Icon(
      icon,
      size: math.max(0, _fin(size)),
      color: color ?? Wv.of(context).accent,
    );
  }
}
