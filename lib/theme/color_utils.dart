import 'package:flutter/material.dart';

/// Small color helpers (replace the flex_color_scheme extensions the player
/// sheet used).
extension ColorShadeX on Color {
  /// Lowers HSL lightness by [amount] percent.
  Color darken([int amount = 10]) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness - amount / 100).clamp(0.0, 1.0))
        .toColor();
  }

  /// Adds [amount] percent of white to every channel.
  Color brighten([int amount = 10]) {
    final add = (255 * amount / 100).round();
    int channel(double v) => ((v * 255).round() + add).clamp(0, 255);
    return Color.fromARGB(
      (a * 255).round(),
      channel(r),
      channel(g),
      channel(b),
    );
  }
}
