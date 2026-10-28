import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// The floating Aqua tray behind the mini-player, the tab bar and the
/// selection bar.
BoxDecoration wvTrayDecoration(WvPalette a, double radius) => BoxDecoration(
  gradient: a.chromeGradient,
  image: a.chromeGrain,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: a.outline.withValues(alpha: 0.55)),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: a.dark ? 0.3 : 0.12),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
    BoxShadow(
      color: Colors.white.withValues(alpha: a.dark ? 0.04 : 0.7),
      offset: const Offset(0, -1),
    ),
  ],
);
