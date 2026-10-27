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
class ThemeCrossFade extends StatefulWidget {
  const ThemeCrossFade({
    super.key,
    required this.themeKey,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
  });

  /// Anything that compares equal while the theme is unchanged.
  final Object themeKey;
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
    if (oldWidget.themeKey != widget.themeKey) _captureOldFrame();
  }

  /// Runs before the children rebuild with the new theme, so the boundary
  /// still holds the previous frame.
  void _captureOldFrame() {
    final object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary || !object.hasSize) return;
    try {
      final ratio = View.of(context).devicePixelRatio.clamp(1.0, 2.0);
      final image = object.toImageSync(pixelRatio: ratio);
      _old?.dispose();
      _old = image;
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
