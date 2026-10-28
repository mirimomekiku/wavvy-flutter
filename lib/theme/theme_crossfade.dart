import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Cross-fades the whole app when its theme changes (light/dark, appearance or
/// album colors).
///
/// Material's own theme animation rebuilds the entire app on every frame for
/// 200 ms, which is what makes a theme switch stutter. Instead the app switches
/// theme at once (one rebuild) and the last frame of the old theme, captured as
/// an image, fades away on top. Changing [themeKey] starts a fade.
///
/// [tintKey] is for a color that changes often (the album color follows every
/// track). A change in it fades more cheaply: at screen resolution, over a
/// shorter time, and not at all while another fade is running, while the app is
/// in the background, or when the new color is close to the old.
class ThemeCrossFade extends StatefulWidget {
  const ThemeCrossFade({
    super.key,
    required this.themeKey,
    required this.child,
    this.tintKey,
    this.duration = const Duration(milliseconds: 320),
  });

  /// Anything that compares equal while the theme is unchanged.
  final Object themeKey;

  /// The accent that follows the music, as an ARGB integer, or null.
  final int? tintKey;
  final Widget child;
  final Duration duration;

  @override
  State<ThemeCrossFade> createState() => _ThemeCrossFadeState();
}

class _ThemeCrossFadeState extends State<ThemeCrossFade>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundary = GlobalKey();
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener(_onStatus);
  late final Animation<double> _opacity = ReverseAnimation(
    CurvedAnimation(parent: _fade, curve: Curves.easeInOut),
  );
  ui.Image? _old;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _release();
  }

  void _release() {
    final image = _old;
    if (image == null) return;
    setState(() => _old = null);
    image.dispose();
  }

  @override
  void didUpdateWidget(ThemeCrossFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.themeKey != widget.themeKey) {
      _captureOldFrame();
    } else if (oldWidget.tintKey != widget.tintKey &&
        _tintWorthFading(oldWidget)) {
      _captureOldFrame(ratio: 1, duration: _tintDuration);
    }
  }

  static const _tintDuration = Duration(milliseconds: 200);

  bool _tintWorthFading(ThemeCrossFade old) {
    if (_fade.isAnimating) return false;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    final from = old.tintKey;
    final to = widget.tintKey;
    if (from == null || to == null) return false;
    return _colorDistance(from, to) > 24;
  }

  /// Straight-line distance between two ARGB colors in RGB space.
  static double _colorDistance(int a, int b) {
    var sum = 0;
    for (final shift in const [16, 8, 0]) {
      final d = ((a >> shift) & 0xFF) - ((b >> shift) & 0xFF);
      sum += d * d;
    }
    return math.sqrt(sum);
  }

  /// Runs before the children rebuild with the new theme, so the boundary
  /// still holds the previous frame.
  void _captureOldFrame({double? ratio, Duration? duration}) {
    final object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary || !object.hasSize) return;
    try {
      final pixelRatio =
          ratio ?? View.of(context).devicePixelRatio.clamp(1.0, 2.0);
      final image = object.toImageSync(pixelRatio: pixelRatio);
      _old?.dispose();
      _old = image;
      _fade.duration = duration ?? widget.duration;
      _fade.forward(from: 0);
    } catch (e) {
      // Debug builds assert if something repainted this frame already; the
      // theme still switches, only the fade is skipped.
      debugPrint('theme cross-fade skipped: $e');
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _old?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (old != null)
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _opacity,
                child: RawImage(image: old, fit: BoxFit.fill),
              ),
            ),
          ),
      ],
    );
  }
}
