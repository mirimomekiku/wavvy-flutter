import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// The two textured looks: Panther's pinstripes and Tiger's brushed aluminum.
enum WvTextureKind { pinstripe, brushed }

/// The texture tiles, made once and kept.
///
/// Each tile is a small `ui.Image` of translucent white/black marks, so it
/// lies over any base color (the page, a chrome gradient, a card in a preview)
/// without knowing it. Tiles are drawn by a fixed, seeded generator: the same
/// pixels every run, no randomness per frame, and nothing is created again
/// after the first request. The Aqua, Graphite and accent looks never ask for
/// one, so they pay nothing.
class WvTextures {
  WvTextures._();

  static final Map<(WvTextureKind, bool), ui.Image> _tiles = {};
  static final Map<(WvTextureKind, bool), ui.Shader> _shaders = {};
  static final Map<(WvTextureKind, bool), DecorationImage> _decorations = {};

  /// Pinstripes: one line in [pinstripePeriod] logical pixels, horizontal as in
  /// Panther.
  static const int pinstripePeriod = 3;

  static const int _brushedWidth = 128;
  static const int _brushedHeight = 64;

  /// The tile for [kind] in light or [dark]; the same image on every call.
  static ui.Image tile(WvTextureKind kind, bool dark) =>
      _tiles.putIfAbsent((kind, dark), () => _make(kind, dark));

  /// A repeating shader over [tile], for painting a whole area in one call.
  /// Logical pixels map to tile pixels one to one, so lines stay crisp.
  static ui.Shader shader(WvTextureKind kind, bool dark) =>
      _shaders.putIfAbsent(
        (kind, dark),
        () => ui.ImageShader(
          tile(kind, dark),
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.none,
        ),
      );

  /// The same tile as a [DecorationImage], for a [BoxDecoration.image] (chrome
  /// bars, trays, previews).
  static DecorationImage decoration(WvTextureKind kind, bool dark) =>
      _decorations.putIfAbsent(
        (kind, dark),
        () => DecorationImage(
          image: _TileProvider(kind, dark),
          repeat: ImageRepeat.repeat,
          fit: BoxFit.none,
          alignment: Alignment.topLeft,
          filterQuality: FilterQuality.none,
        ),
      );

  static ui.Image _make(WvTextureKind kind, bool dark) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final int w, h;
    switch (kind) {
      case WvTextureKind.pinstripe:
        w = 2;
        h = pinstripePeriod;
        // A barely different tint of the surface: dark lines on paper, light
        // ones on slate.
        canvas.drawRect(
          Rect.fromLTWH(0, 0, w.toDouble(), 1),
          Paint()
            ..color = dark ? const Color(0x12FFFFFF) : const Color(0x16000000),
        );
      case WvTextureKind.brushed:
        w = _brushedWidth;
        h = _brushedHeight;
        _paintGrain(canvas, dark);
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    return image;
  }

  /// Fine horizontal streaks of varying length and brightness. Streaks that run
  /// off the right edge continue on the left, so the tile repeats seamlessly.
  static void _paintGrain(Canvas canvas, bool dark) {
    var state = dark ? 0x2F6A1D93 : 0x1B3C5E71;
    int next() {
      // A small 31-bit LCG: fixed seed, fixed output.
      state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
      return state >> 8;
    }

    final paint = Paint();
    for (var y = 0; y < _brushedHeight; y++) {
      for (var k = 0; k < 7; k++) {
        final x = next() % _brushedWidth;
        final length = 14 + next() % 84;
        final light = next() % 100 < (dark ? 55 : 60);
        final strength = (next() % 100) / 100;
        final alpha = light
            ? (dark ? 0.015 + 0.06 * strength : 0.03 + 0.12 * strength)
            : (dark ? 0.03 + 0.10 * strength : 0.015 + 0.055 * strength);
        paint.color = (light ? Colors.white : Colors.black).withValues(
          alpha: alpha,
        );
        final row = y.toDouble();
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), row, length.toDouble(), 1),
          paint,
        );
        if (x + length > _brushedWidth) {
          canvas.drawRect(
            Rect.fromLTWH(
              (x - _brushedWidth).toDouble(),
              row,
              length.toDouble(),
              1,
            ),
            paint,
          );
        }
      }
    }
  }
}

/// Serves a cached tile to [DecorationImage]. Equal providers resolve to the
/// one image in the cache, and each stream holds its own handle on it.
@immutable
class _TileProvider extends ImageProvider<_TileProvider> {
  const _TileProvider(this.kind, this.dark);
  final WvTextureKind kind;
  final bool dark;

  @override
  Future<_TileProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _TileProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture(ImageInfo(image: WvTextures.tile(kind, dark).clone())),
  );

  @override
  bool operator ==(Object other) =>
      other is _TileProvider && other.kind == kind && other.dark == dark;

  @override
  int get hashCode => Object.hash(kind, dark);
}

/// The page behind a screen's content, for the textured looks: the opaque page
/// color, the texture and then the screen.
///
/// Scaffolds in these looks set `backgroundColor: a.pageColor` (transparent
/// when textured) so the texture shows through, while this widget supplies the
/// opaque color underneath: a page sliding in or out of a transition therefore
/// hides whatever is behind it, as an ordinary Scaffold does. The texture sits
/// in its own [RepaintBoundary], painted once and kept as a layer while the
/// content scrolls above it. For Aqua, Graphite and the accent looks this
/// returns [child] unchanged: no extra layer.
class WvBackdrop extends StatelessWidget {
  const WvBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final kind = a.textureKind;
    if (kind == null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: WvTexturePainter(
                kind: kind,
                dark: a.dark,
                base: a.background,
                gradient: a.backdropGradient,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Paints the opaque base, an optional silver gradient and then the texture.
class WvTexturePainter extends CustomPainter {
  const WvTexturePainter({
    required this.kind,
    required this.dark,
    required this.base,
    this.gradient,
  });

  final WvTextureKind kind;
  final bool dark;
  final Color base;
  final Gradient? gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    if (gradient != null) {
      canvas.drawRect(rect, Paint()..shader = gradient!.createShader(rect));
    }
    canvas.drawRect(rect, Paint()..shader = WvTextures.shader(kind, dark));
  }

  @override
  bool shouldRepaint(WvTexturePainter old) =>
      old.kind != kind ||
      old.dark != dark ||
      old.base != base ||
      old.gradient != gradient;
}
