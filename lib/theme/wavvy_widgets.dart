import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_texture.dart';

/// Kaisu-inspired paper surfaces, silver chrome and Aqua selection states.
///
/// The color themes are Kaisu's: Aqua (blue) and its accent colors, made by
/// turning Aqua's blue around the color wheel (see [WvPalette.hueShift]), plus
/// Graphite, and two textured looks from Mac OS X: Pinstripe (Panther) and
/// Brushed Metal (Tiger). The textures live in `wavvy_texture.dart`.
enum WvAppearance {
  aqua,
  orange,
  green,
  purple,
  pink,
  red,
  teal,
  graphite,
  pinstripe,
  brushedMetal,
}

/// Colors for the current brightness + accent, exposed as a [ThemeExtension]
/// so every widget reads it with [Wv.of].
///
/// Everything is derived from one Material [scheme]; the named roles below are
/// short, stable aliases for it.
@immutable
class WvPalette extends ThemeExtension<WvPalette> {
  final bool dark;
  final WvAppearance appearance;

  /// Album-art color (Dynamic Colors). When set (and not near-gray) it
  /// replaces the appearance's own seed.
  final Color? seed;

  /// The full Material 3 color scheme everything below is read from.
  final ColorScheme scheme;

  WvPalette({required this.dark, required this.appearance, this.seed})
    : scheme = _schemeFor(dark, appearance, seed);

  const WvPalette._(this.dark, this.appearance, this.seed, this.scheme);

  /// Used when no theme is available (should not normally happen).
  static final WvPalette fallback = WvPalette(
    dark: true,
    appearance: WvAppearance.aqua,
  );

  /// Kaisu makes its accent colors by turning Aqua's blue around the color
  /// wheel by these many degrees; so does Wavvy, so a theme looks the same on
  /// both. Aqua itself is not turned.
  static const Map<WvAppearance, double> hueShift = {
    WvAppearance.orange: 175,
    WvAppearance.green: 265,
    WvAppearance.purple: 65,
    WvAppearance.pink: 115,
    WvAppearance.red: 145,
    WvAppearance.teal: 320,
  };

  static bool _usable(Color? seed) =>
      seed != null && HSLColor.fromColor(seed).saturation >= 0.12;

  static Color _turn(Color c, double degrees) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withHue((hsl.hue + degrees) % 360).toColor();
  }

  static double _contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
  }

  /// [c], darkened ([darker]) or lightened until it reads against [background]
  /// at [minimum] contrast. Turning a blue to yellow-orange or green leaves it
  /// brighter, and text in it would otherwise be hard to read.
  static Color _readable(
    Color c,
    Color background, {
    required bool darker,
    double minimum = 4.5,
  }) {
    var hsl = HSLColor.fromColor(c);
    var out = c;
    for (var i = 0; i < 40 && _contrast(out, background) < minimum; i++) {
      hsl = hsl.withLightness(
        (hsl.lightness + (darker ? -0.02 : 0.02)).clamp(0.0, 1.0),
      );
      out = hsl.toColor();
    }
    return out;
  }

  /// White or near-black, whichever reads better on [background].
  static Color _onColor(Color background, Color preferred) {
    if (_contrast(preferred, background) >= 4.5) return preferred;
    const dark = Color(0xFF111418);
    return _contrast(Colors.white, background) >= _contrast(dark, background)
        ? Colors.white
        : dark;
  }

  static ColorScheme _schemeFor(
    bool dark,
    WvAppearance appearance,
    Color? seed,
  ) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    ColorScheme from(Color c, {double shift = 0}) {
      final base = ColorScheme.fromSeed(seedColor: c, brightness: brightness);
      return base.copyWith(
        surface: dark ? const Color(0xFF15191F) : const Color(0xFFECECEC),
        onSurface: dark ? const Color(0xFFF0F3F7) : const Color(0xFF1C1C1C),
        onSurfaceVariant: dark
            ? const Color(0xFFB3BECD)
            : const Color(0xFF4B4B4B),
        surfaceContainer: dark ? const Color(0xFF1E242D) : Colors.white,
        surfaceContainerHigh: dark
            ? const Color(0xFF252D38)
            : const Color(0xFFF0F3F7),
        surfaceContainerHighest: dark
            ? const Color(0xFF303B49)
            : const Color(0xFFE4EAF1),
        outline: dark ? const Color(0xFF9AA9BC) : const Color(0xFF6A7889),
        outlineVariant: dark
            ? const Color(0xFF364250)
            : const Color(0xFFD6DAE0),
        primaryContainer: _turn(
          dark ? const Color(0xFF193958) : const Color(0xFFE8F1FC),
          shift,
        ),
        onPrimaryContainer: _turn(
          dark ? const Color(0xFFCDDEFA) : const Color(0xFF173D72),
          shift,
        ),
        secondaryContainer: dark
            ? const Color(0xFF293849)
            : const Color(0xFFE7EDF5),
        onSecondaryContainer: dark
            ? const Color(0xFFD0DDEB)
            : const Color(0xFF283F59),
        tertiaryContainer: dark
            ? const Color(0xFF273745)
            : const Color(0xFFECF1F7),
        onTertiaryContainer: dark
            ? const Color(0xFFD0DDEB)
            : const Color(0xFF283F59),
      );
    }

    // Album colors: the whole scheme comes from the artwork (the textured
    // looks keep their own neutral page and surfaces).
    if (_usable(seed)) return _neutrals(from(seed!), dark, appearance);

    if (appearance == WvAppearance.brushedMetal) {
      // Steel blue accent; the controls keep Aqua's gel.
      final primary = dark ? const Color(0xFFA6BCD8) : const Color(0xFF3A5A82);
      return _neutrals(
        from(const Color(0xFF3F5F86)).copyWith(
          primary: primary,
          onPrimary: dark ? const Color(0xFF14202E) : Colors.white,
        ),
        dark,
        appearance,
      );
    }

    if (appearance == WvAppearance.graphite) {
      return from(const Color(0xFF526174)).copyWith(
        primary: dark ? const Color(0xFFBDC6D0) : const Color(0xFF536172),
        onPrimary: dark ? const Color(0xFF18232E) : Colors.white,
      );
    }

    // Aqua, and its accents turned around the color wheel.
    final shift = hueShift[appearance] ?? 0;
    final pinstripe = appearance == WvAppearance.pinstripe;
    final page = dark ? const Color(0xFF1E242D) : const Color(0xFFECECEC);
    final primary = _readable(
      _turn(
        dark
            ? Color(pinstripe ? 0xFF7FB0F7 : 0xFF8CB9F5)
            : Color(pinstripe ? 0xFF2B68C9 : 0xFF356FCB),
        shift,
      ),
      page,
      darker: !dark,
    );
    final scheme = from(_turn(const Color(0xFF2563B2), shift), shift: shift)
        .copyWith(
          primary: primary,
          onPrimary: _onColor(
            primary,
            _turn(dark ? const Color(0xFF10233D) : Colors.white, shift),
          ),
        );
    return pinstripe ? _neutrals(scheme, dark, appearance) : scheme;
  }

  /// The page and surface colors of the textured looks, over any accent.
  static ColorScheme _neutrals(ColorScheme s, bool dark, WvAppearance a) {
    switch (a) {
      case WvAppearance.pinstripe:
        // Panther: near-white paper with white cards; dark slate at night.
        return s.copyWith(
          surface: dark ? const Color(0xFF1A1F26) : const Color(0xFFF1F1F1),
          surfaceContainerHigh: dark
              ? const Color(0xFF262E39)
              : const Color(0xFFF7F7F8),
        );
      case WvAppearance.brushedMetal:
        // Tiger: silver aluminum, cool steel in the dark.
        return s.copyWith(
          surface: dark ? const Color(0xFF23272D) : const Color(0xFFD7D9DD),
          surfaceContainer: dark
              ? const Color(0xFF2C3138)
              : const Color(0xFFEDEEF0),
          surfaceContainerHigh: dark
              ? const Color(0xFF353B43)
              : const Color(0xFFF3F4F6),
          surfaceContainerHighest: dark
              ? const Color(0xFF414852)
              : const Color(0xFFDCDFE4),
          outlineVariant: dark
              ? const Color(0xFF444B55)
              : const Color(0xFFB4B9C1),
        );
      default:
        return s;
    }
  }

  // ------------------------------------------------------------- Surfaces

  Color get background => scheme.surface;
  Color get surface => scheme.surfaceContainer;
  Color get surfaceHigh => scheme.surfaceContainerHigh;
  Color get surfaceHighest => scheme.surfaceContainerHighest;
  Color get separator => scheme.outlineVariant;
  Color get outline => scheme.outline;
  Color get shellBottom =>
      dark ? const Color(0xFF222A34) : const Color(0xFFE4E9EF);
  Color get stripe => switch (appearance) {
    WvAppearance.brushedMetal =>
      dark ? const Color(0xFF30363D) : const Color(0xFFE3E5E9),
    _ => dark ? const Color(0xFF1B222C) : const Color(0xFFF1F5FB),
  };

  // ------------------------------------------------------------- Textures

  /// The texture of this look, or null for the plain ones.
  WvTextureKind? get textureKind => switch (appearance) {
    WvAppearance.pinstripe => WvTextureKind.pinstripe,
    WvAppearance.brushedMetal => WvTextureKind.brushed,
    _ => null,
  };

  /// What a Scaffold on a screen wrapped in a `WvBackdrop` (or `WvSystemUi`)
  /// uses as its background: transparent when textured, so the texture
  /// behind it shows, otherwise [background].
  Color get pageColor => textureKind == null ? background : Colors.transparent;

  /// A silver sheen under the brushed grain, or null.
  Gradient? get backdropGradient => appearance == WvAppearance.brushedMetal
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0x14FFFFFF), Color(0x00FFFFFF), Color(0x14000000)]
              : const [Color(0x66FFFFFF), Color(0x00FFFFFF), Color(0x14000000)],
        )
      : null;

  /// Brushed grain for toolbars, trays and sheet headers
  /// (`BoxDecoration.image`); null for every other look.
  DecorationImage? get chromeGrain => appearance == WvAppearance.brushedMetal
      ? WvTextures.decoration(WvTextureKind.brushed, dark)
      : null;

  /// The page texture as a [DecorationImage], for small previews.
  DecorationImage? get pageTexture {
    final kind = textureKind;
    return kind == null ? null : WvTextures.decoration(kind, dark);
  }

  LinearGradient get chromeGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: appearance == WvAppearance.brushedMetal
        ? (dark
              ? const [Color(0xFF50565F), Color(0xFF3A4048), Color(0xFF2C3036)]
              : const [Color(0xFFF4F5F7), Color(0xFFDCDFE3), Color(0xFFC3C7CE)])
        : dark
        ? const [Color(0xFF3B414A), Color(0xFF2B3038), Color(0xFF22272F)]
        : const [Color(0xFFF7F7F7), Color(0xFFE2E3E5), Color(0xFFCDD0D4)],
    stops: const [0, 0.48, 1],
  );
  LinearGradient gelGradient({bool primary = false}) => primary
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(accent, Colors.white, 0.48)!,
            Color.lerp(accent, Colors.white, 0.12)!,
            accent,
            Color.lerp(accent, Colors.white, 0.13)!,
          ],
          stops: const [0, 0.45, 0.52, 1],
        )
      : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [
                  Color(0xFF555C65),
                  Color(0xFF3B424C),
                  Color(0xFF303740),
                  Color(0xFF3F4852),
                ]
              : const [
                  Color(0xFFFEFEFE),
                  Color(0xFFEBEBEB),
                  Color(0xFFD6D6D6),
                  Color(0xFFE6E6E6),
                ],
          stops: const [0, 0.48, 0.52, 1],
        );
  BoxDecoration get lcdDecoration => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: dark
          ? const [Color(0xFF161E23), Color(0xFF253238), Color(0xFF29363D)]
          : const [Color(0xFFDDE4E2), Color(0xFFF2F5F3), Color(0xFFFBFCFB)],
      stops: const [0, 0.4, 1],
    ),
    border: Border.all(
      color: dark ? const Color(0xFF12171D) : const Color(0xFF8C959B),
    ),
    borderRadius: BorderRadius.circular(5),
    boxShadow: [
      BoxShadow(
        color: Colors.white.withValues(alpha: dark ? 0.04 : 0.8),
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.10),
        blurRadius: 2,
        offset: const Offset(0, -1),
      ),
    ],
  );

  BoxDecoration frame({Color? color, double radius = 8, bool raised = true}) =>
      BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: separator),
        boxShadow: raised
            ? [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: dark ? 0.12 : 0.035),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      );

  // ----------------------------------------------------------------- Text

  Color get text => scheme.onSurface;
  Color get textSecondary => scheme.onSurfaceVariant;
  Color get textTertiary => scheme.outline;

  // --------------------------------------------------------------- Accent

  /// Primary: the main action, active indicators and progress.
  Color get accent => scheme.primary;

  /// Accent for text and icons sitting directly on [background].
  Color get accentText => scheme.primary;

  /// Content drawn on top of [accent].
  Color get onAccent => scheme.onPrimary;

  // Tonal containers (color blocking).
  Color get primaryContainer => scheme.primaryContainer;
  Color get onPrimaryContainer => scheme.onPrimaryContainer;
  Color get secondaryContainer => scheme.secondaryContainer;
  Color get onSecondaryContainer => scheme.onSecondaryContainer;
  Color get tertiary => scheme.tertiary;
  Color get onTertiary => scheme.onTertiary;
  Color get tertiaryContainer => scheme.tertiaryContainer;
  Color get onTertiaryContainer => scheme.onTertiaryContainer;
  Color get error => scheme.error;

  /// Rotating tonal "color block" pairs (container, content-on-container):
  /// primary, secondary, tertiary containers. Use [i] (an index or a hash) to
  /// give neighbouring tiles different colors, Material 3 Expressive style.
  (Color, Color) tonal(int i) {
    switch (i.abs() % 3) {
      case 0:
        return (primaryContainer, onPrimaryContainer);
      case 1:
        return (tertiaryContainer, onTertiaryContainer);
      default:
        return (secondaryContainer, onSecondaryContainer);
    }
  }

  /// Selected chip / segmented item (Material You uses secondaryContainer).
  Color get chipSelected => scheme.primaryContainer;

  /// Text on a selected chip.
  Color get onChipSelected => scheme.onPrimaryContainer;

  /// Background for now-playing surfaces. The scheme itself is generated from
  /// the album color while a song with artwork plays, so its primary container
  /// is already album-tinted.
  Color tint(Color? source) => source == null ? background : primaryContainer;

  @override
  WvPalette copyWith({
    bool? dark,
    WvAppearance? appearance,
    Color? seed,
    bool clearSeed = false,
  }) => WvPalette(
    dark: dark ?? this.dark,
    appearance: appearance ?? this.appearance,
    seed: clearSeed ? null : (seed ?? this.seed),
  );

  @override
  WvPalette lerp(ThemeExtension<WvPalette>? other, double t) {
    if (other is! WvPalette) return this;
    final base = t < 0.5 ? this : other;
    // Blend the whole tonal scheme so album changes and light/dark switches
    // cross-fade instead of snapping.
    return WvPalette._(
      base.dark,
      base.appearance,
      (seed != null && other.seed != null)
          ? Color.lerp(seed, other.seed, t)
          : base.seed,
      ColorScheme.lerp(scheme, other.scheme, t),
    );
  }
}

class Wv {
  Wv._();

  static WvPalette of(BuildContext context) =>
      Theme.of(context).extension<WvPalette>() ?? WvPalette.fallback;
}

/// Shared spacing, rounded frames and short press animations.
class Ds {
  Ds._();

  static const double radiusS = 10;
  static const double radiusM = 6;
  static const double radiusL = 8;
  static const double radiusXL = 12;
  static const double hairline = 1;

  /// "Leaf" corners: two opposite corners big, two small. Alternating leaf A /
  /// leaf B / rounded tiles gives grids a playful, hand-cut rhythm.
  static const BorderRadius leafA = BorderRadius.only(
    topLeft: Radius.circular(40),
    bottomRight: Radius.circular(40),
    topRight: Radius.circular(14),
    bottomLeft: Radius.circular(14),
  );
  static const BorderRadius leafB = BorderRadius.only(
    topRight: Radius.circular(40),
    bottomLeft: Radius.circular(40),
    topLeft: Radius.circular(14),
    bottomRight: Radius.circular(14),
  );

  /// Rotating playful corner style for the i-th tile of a grid/shelf.
  static BorderRadius tileShape(int i) => BorderRadius.circular(16);

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 250);

  /// Springy, slightly overshooting motion for shape/size changes.
  static const Curve spring = Curves.easeOutCubic;
  static const Duration springDuration = Duration(milliseconds: 200);

  static Color separator(BuildContext context) => Wv.of(context).separator;
}

/// Flat bar background (toolbars and the bottom area).
class WvBar extends StatelessWidget {
  final Widget child;

  /// Kept for call-site compatibility; the flat style has no top/bottom edge.
  final bool topBar;
  final Color? color;

  const WvBar({super.key, required this.child, this.topBar = true, this.color});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Material(color: color ?? a.background, child: child);
  }
}

/// Button used everywhere in the app (Material 3 Expressive style: it
/// morphs its shape while pressed).
///
///  * [circular] icon buttons: transparent by default, [primary] = primary
///    fill, [inverse] = primary-container fill (the big play button);
///  * labeled capsules ([circular] false): tonal (secondary container) by
///    default, [primary] = primary pill, [inverse] = primary-container pill.
///  * [squircle] keeps the resting shape a rounded square (e.g. the play button
///    while paused) so state changes read as a shape morph.
///
/// The visible size is small but the hit area is always 48dp.
class WvButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool primary;
  final bool inverse;
  final bool circular;
  final bool squircle;
  final double size;
  final double? width;
  final String? tooltip;

  const WvButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.primary = false,
    this.inverse = false,
    this.circular = false,
    this.squircle = false,
    this.size = 32,
    this.width,
    this.tooltip,
  });

  @override
  State<WvButton> createState() => _WvButtonState();
}

class _WvButtonState extends State<WvButton> {
  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final enabled = widget.onPressed != null;
    final fg = widget.primary ? a.onAccent : a.text;
    final radius = widget.circular && !widget.squircle
        ? widget.size / 2
        : widget.squircle
        ? 6.0
        : 16.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final decoration = BoxDecoration(
      gradient: a.gelGradient(primary: widget.primary),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: widget.primary
            ? Color.lerp(a.accent, Colors.black, 0.25)!
            : a.outline.withValues(alpha: 0.65),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: a.dark ? 0.25 : 0.14),
          blurRadius: 1,
          offset: const Offset(0, 1),
        ),
      ],
    );
    final style = TextButton.styleFrom(
      foregroundColor: fg,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      disabledForegroundColor: a.textTertiary,
      minimumSize: Size(
        widget.circular ? widget.size.clamp(32.0, 100.0) : (widget.width ?? 72),
        widget.size.clamp(32.0, 100.0),
      ),
      padding: widget.circular
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12),
      shape: shape,
      textStyle: TextStyle(
        fontFamily: 'WorkSans',
        fontSize: 13,
        fontWeight: widget.primary ? FontWeight.w600 : FontWeight.w500,
        shadows: widget.primary
            ? const [Shadow(color: Color(0x66305792), offset: Offset(0, -1))]
            : null,
      ),
    );
    Widget result = Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: decoration,
        child: TextButton(
          style: style,
          onPressed: widget.onPressed,
          child: IconTheme(
            data: IconThemeData(
              size: widget.circular
                  ? (widget.size * 0.48).clamp(18.0, 32.0)
                  : 18,
              color: enabled ? fg : a.textTertiary,
            ),
            child: widget.circular
                ? widget.child
                : FittedBox(fit: BoxFit.scaleDown, child: widget.child),
          ),
        ),
      ),
    );
    if (widget.width != null && !widget.circular) {
      result = SizedBox(width: widget.width, child: result);
    }
    if (!enabled) result = Opacity(opacity: 0.55, child: result);
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

/// Row of toggle chips. Shape morphs on selection: the selected chip is a full
/// pill in the secondary container, the others are rounded squares. With
/// [indicator] a short accent bar sits under the selected chip.
///
/// [uppercase] renders compact, letter-spaced labels (used by the Library and
/// Search source toggles).
class WvChips extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool uppercase;
  final bool indicator;

  /// When set, each chip shows its icon instead of its label (the label is kept
  /// for the tooltip and screen readers). Must match [labels] in length.
  final List<IconData>? icons;

  const WvChips({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.uppercase = false,
    this.indicator = false,
    this.icons,
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < labels.length; i++)
            Semantics(
              button: true,
              selected: selected == i,
              label: labels[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.horizontal(
                    left: i == 0 ? const Radius.circular(6) : Radius.zero,
                    right: i == labels.length - 1
                        ? const Radius.circular(6)
                        : Radius.zero,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: a.gelGradient(primary: i == selected),
                      border: Border.all(
                        color: i == selected
                            ? a.accent
                            : a.outline.withValues(alpha: 0.6),
                      ),
                    ),
                    child: InkWell(
                      onTap: () => onChanged(i),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 36),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: uppercase ? 12 : 14,
                            vertical: 8,
                          ),
                          child: icons != null
                              ? Tooltip(
                                  message: labels[i],
                                  child: Icon(
                                    icons![i],
                                    size: 20,
                                    color: i == selected ? a.onAccent : a.text,
                                  ),
                                )
                              : Text(
                                  uppercase
                                      ? labels[i].toUpperCase()
                                      : labels[i],
                                  style: TextStyle(
                                    fontSize: uppercase ? 11 : 12,
                                    fontWeight: i == selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: i == selected ? a.onAccent : a.text,
                                    letterSpacing: uppercase ? 0.2 : 0,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Search field look-alike (a Material 3 search bar) that opens search when
/// tapped.
class WvSearchField extends StatelessWidget {
  final VoidCallback onTap;
  final String hint;

  const WvSearchField({super.key, required this.onTap, this.hint = "Search"});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);

    return Semantics(
      button: true,
      label: hint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: a.surfaceHigh,
                borderRadius: BorderRadius.circular(Ds.radiusM),
                border: Border.all(
                  color: a.outline.withValues(alpha: 0.6),
                  width: 1.4,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 24, color: a.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: a.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded tonal card.
class WvPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  const WvPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.color,
    this.radius = Ds.radiusM,
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);

    return Container(
      padding: padding,
      decoration: a.frame(color: color, radius: radius),
      child: child,
    );
  }
}

/// Thin progress line (display only).
class WvProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color? color;
  final Color? trackColor;
  final double height;

  const WvProgressBar({
    super.key,
    required this.value,
    this.color,
    this.trackColor,
    this.height = 4,
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final v = value.clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: trackColor ?? a.surfaceHighest),
            ),
            FractionallySizedBox(
              widthFactor: v,
              child: ColoredBox(color: color ?? a.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bold section title with an optional trailing action ("Show all").
class WvSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const WvSectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);

    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 24, bottom: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: a.text,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Artwork with big rounded corners (or a circle). Optional shadow for large
/// hero artwork.
class WvArtwork extends StatelessWidget {
  final Widget child;
  final bool circular;
  final double radius;
  final bool elevated;

  /// Overrides [radius] with an arbitrary corner shape (e.g. [Ds.tileShape]).
  final BorderRadius? shape;

  const WvArtwork({
    super.key,
    required this.child,
    this.circular = false,
    this.radius = Ds.radiusM,
    this.elevated = false,
    this.shape,
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: a.separator, width: 1),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular
            ? null
            : (shape ?? BorderRadius.circular(radius)),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: a.scheme.shadow.withValues(alpha: a.dark ? 0.2 : 0.1),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: circular
          ? ClipOval(child: child)
          : ClipRRect(
              borderRadius: shape ?? BorderRadius.circular(radius),
              child: child,
            ),
    );
  }
}

/// Label above an [InsetGroup].
class GroupHeader extends StatelessWidget {
  final String title;

  const GroupHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: Text(
        title,
        style: TextStyle(
          color: a.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

/// Material 3 Expressive segmented list: items sit in separate tonal tiles
/// with small gaps; only the outer corners are large.
class InsetGroup extends StatelessWidget {
  final List<Widget> children;

  /// Kept for call-site compatibility (the segmented style has no dividers).
  final double dividerIndent;

  const InsetGroup({
    super.key,
    required this.children,
    this.dividerIndent = 64,
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    // Aqua group box: soft panel, fine outline, white lip below.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: a.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: a.outline.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: a.dark ? 0.04 : 0.75),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(height: 1, indent: dividerIndent, color: a.separator),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Small tinted icon tile with a squircle shape.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.36),
        color: color.withValues(alpha: 0.18),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}
