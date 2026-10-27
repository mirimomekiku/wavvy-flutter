import 'package:flutter/material.dart';

/// Classic Mac OS X "Aqua" (Snow Leopard / iTunes 10) building blocks.
///
/// The signature materials are:
///  * "gel": a glossy gradient with a hard split at 50% (light top half,
///    darker bottom half) used for buttons, checkboxes and selections;
///  * a brushed light-gray toolbar gradient with dark/light edge lines;
///  * striped table rows and an inset "LCD" display.

enum AquaAppearance { blue, graphite }

/// Colors for the current brightness + appearance, exposed as a
/// [ThemeExtension] so every widget reads it with [Aqua.of].
@immutable
class AquaPalette extends ThemeExtension<AquaPalette> {
  final bool dark;
  final AquaAppearance appearance;

  /// Album-art color (Dynamic Colors). When set (and not near-gray) it
  /// replaces the blue/graphite gel, selection and accent colors.
  final Color? seed;

  const AquaPalette({
    required this.dark,
    required this.appearance,
    this.seed,
  });

  bool get _blue => appearance == AquaAppearance.blue;

  bool get _useSeed =>
      seed != null && HSLColor.fromColor(seed!).saturation >= 0.12;

  /// A tone of the seed at lightness offset [dl] from a clamped mid-tone.
  Color _tone(double dl) {
    final hsl = HSLColor.fromColor(seed!);
    final sat = hsl.saturation.clamp(0.35, 0.85);
    final light = (hsl.lightness.clamp(0.38, 0.56) + dl).clamp(0.0, 1.0);
    return hsl.withSaturation(sat).withLightness(light).toColor();
  }

  // --- Surfaces & text ---
  Color get background =>
      dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  Color get stripe => dark ? const Color(0xFF262A30) : const Color(0xFFEFF3FA);
  Color get text => dark ? const Color(0xFFEDEDED) : const Color(0xFF1A1A1A);
  Color get textSecondary =>
      dark ? const Color(0xFF9C9C9C) : const Color(0xFF6B6B6B);
  Color get separator =>
      dark ? const Color(0xFF3A3A3A) : const Color(0xFFD0D0D0);
  Color get glyph => dark ? const Color(0xFFE6E6E6) : const Color(0xFF333333);
  Color get border => dark ? const Color(0xFF000000) : const Color(0xFF9A9A9A);

  // --- Toolbar / bars ---
  List<Color> get toolbar => dark
      ? const [Color(0xFF5E5E5E), Color(0xFF2D2D2D)]
      : const [Color(0xFFE8E8E8), Color(0xFFB5B5B5)];
  Color get toolbarBorder =>
      dark ? const Color(0xFF000000) : const Color(0xFF6F6F6F);
  Color get toolbarHighlight =>
      dark ? const Color(0xFF6E6E6E) : const Color(0xFFF7F7F7);

  List<Color> get header => dark
      ? const [Color(0xFF4A4A4A), Color(0xFF333333)]
      : const [Color(0xFFF6F6F6), Color(0xFFDADADA)];
  Color get headerBorder =>
      dark ? const Color(0xFF1A1A1A) : const Color(0xFFB0B0B0);

  // --- Gel (4 colors, split at 50%) ---
  List<Color> get gelGray => dark
      ? const [
          Color(0xFF8A8A8A),
          Color(0xFF5A5A5A),
          Color(0xFF3E3E3E),
          Color(0xFF4F4F4F),
        ]
      : const [
          Color(0xFFFFFFFF),
          Color(0xFFE6E6E6),
          Color(0xFFD2D2D2),
          Color(0xFFE4E4E4),
        ];
  Color get gelBorder =>
      dark ? const Color(0xFF111111) : const Color(0xFF7E7E7E);

  List<Color> get gelBlue => _useSeed
      ? [_tone(0.24), _tone(0.10), _tone(-0.04), _tone(0.08)]
      : _blue
      ? const [
          Color(0xFFAFD2F6),
          Color(0xFF72AAEC),
          Color(0xFF3C84DE),
          Color(0xFF6DB1F6),
        ]
      : const [
          Color(0xFFCDD2D8),
          Color(0xFF98A0AB),
          Color(0xFF6B7480),
          Color(0xFF949CA8),
        ];
  Color get gelBlueBorder => _useSeed
      ? _tone(-0.22)
      : (_blue ? const Color(0xFF2A5CA8) : const Color(0xFF4D5560));

  // --- Selection (list rows) ---
  List<Color> get selection => _useSeed
      ? [_tone(0.12), _tone(-0.04)]
      : _blue
      ? const [Color(0xFF6AA8EE), Color(0xFF2D70D2)]
      : const [Color(0xFFA9B0BA), Color(0xFF6A7380)];
  Color get selectionBorder => _useSeed
      ? _tone(-0.16)
      : (_blue ? const Color(0xFF2A62B8) : const Color(0xFF59616D));

  /// Links and accents.
  Color get accent => _useSeed
      ? _tone(dark ? 0.18 : -0.06)
      : _blue
      ? (dark ? const Color(0xFF6FA5F0) : const Color(0xFF1F5FBF))
      : (dark ? const Color(0xFFB4BBC6) : const Color(0xFF4E5868));

  // --- LCD display ---
  List<Color> get lcd => dark
      ? const [Color(0xFF141516), Color(0xFF2A2C2E)]
      : const [Color(0xFFCED2D2), Color(0xFFEDEFEF)];
  Color get lcdBorder =>
      dark ? const Color(0xFF000000) : const Color(0xFF74777A);

  // --- Photo frames ---
  Color get frame => dark ? const Color(0xFF3A3A3A) : const Color(0xFFFFFFFF);
  Color get frameBorder =>
      dark ? const Color(0xFF000000) : const Color(0xFFB5B5B5);

  @override
  AquaPalette copyWith({
    bool? dark,
    AquaAppearance? appearance,
    Color? seed,
    bool clearSeed = false,
  }) => AquaPalette(
    dark: dark ?? this.dark,
    appearance: appearance ?? this.appearance,
    seed: clearSeed ? null : (seed ?? this.seed),
  );

  @override
  AquaPalette lerp(ThemeExtension<AquaPalette>? other, double t) {
    if (other is! AquaPalette) return this;
    final base = t < 0.5 ? this : other;
    // Fade between two album colors instead of snapping.
    final Color? mixed = (seed != null && other.seed != null)
        ? Color.lerp(seed, other.seed, t)
        : base.seed;
    return AquaPalette(
      dark: base.dark,
      appearance: base.appearance,
      seed: mixed,
    );
  }
}

class Aqua {
  Aqua._();

  static AquaPalette of(BuildContext context) =>
      Theme.of(context).extension<AquaPalette>() ??
      const AquaPalette(dark: false, appearance: AquaAppearance.blue);

  /// Gel gradient: light top half, darker bottom half, hard split.
  static LinearGradient gel(List<Color> c) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: c,
    stops: const [0.0, 0.5, 0.5, 1.0],
  );

  static List<Color> darken(List<Color> colors, [double amount = 0.1]) {
    return colors.map((c) {
      final hsl = HSLColor.fromColor(c);
      return hsl
          .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
          .toColor();
    }).toList();
  }
}

/// Spacing, radii and motion constants (Aqua uses small radii, crisp 1px
/// lines and quick ease-out animations).
class Ds {
  Ds._();

  static const double radiusS = 4;
  static const double radiusM = 6;
  static const double radiusL = 10;
  static const double hairline = 1;

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration medium = Duration(milliseconds: 250);
  static const Curve emphasized = Curves.easeOut;

  static Color separator(BuildContext context) => Aqua.of(context).separator;
}

/// Brushed-metal bar. [topBar] puts the dark edge on the bottom (a toolbar);
/// otherwise the dark edge is on top (a bottom bar).
class AquaBar extends StatelessWidget {
  final Widget child;
  final bool topBar;

  const AquaBar({super.key, required this.child, this.topBar = true});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    final dark = BorderSide(color: a.toolbarBorder);
    final light = BorderSide(color: a.toolbarHighlight);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: a.toolbar,
        ),
        border: Border(
          top: topBar ? light : dark,
          bottom: topBar ? dark : light,
        ),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Glossy Aqua push button. Circular for transport controls, capsule for
/// toolbar buttons. Visible size is small but the hit area is always 48dp.
class GelButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool primary;
  final bool circular;
  final double size;
  final double? width;
  final String? tooltip;

  const GelButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.primary = false,
    this.circular = false,
    this.size = 30,
    this.width,
    this.tooltip,
  });

  @override
  State<GelButton> createState() => _GelButtonState();
}

class _GelButtonState extends State<GelButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    final enabled = widget.onPressed != null;

    var colors = widget.primary ? a.gelBlue : a.gelGray;
    if (_down && enabled) colors = Aqua.darken(colors, 0.12);
    final borderColor = widget.primary ? a.gelBlueBorder : a.gelBorder;
    final glyphColor = widget.primary ? Colors.white : a.glyph;

    final double w = widget.circular
        ? widget.size
        : (widget.width ?? widget.size * 1.4);

    final visual = AnimatedContainer(
      duration: Ds.fast,
      width: w,
      height: widget.size,
      decoration: BoxDecoration(
        gradient: Aqua.gel(colors),
        shape: widget.circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.circular
            ? null
            : BorderRadius.circular(widget.size / 2),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: a.dark ? 0.06 : 0.7),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: IconTheme(
        data: IconThemeData(color: glyphColor, size: widget.size * 0.56),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: glyphColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          child: Center(child: widget.child),
        ),
      ),
    );

    Widget result = Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Opacity(opacity: enabled ? 1 : 0.45, child: visual),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

/// Aqua checkbox: gel square, white check when on.
class AquaCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AquaCheckbox({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    final colors = value ? a.gelBlue : a.gelGray;
    final border = value ? a.gelBlueBorder : a.gelBorder;

    return Semantics(
      checked: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: Ds.fast,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                gradient: Aqua.gel(colors),
                borderRadius: BorderRadius.circular(Ds.radiusS),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: a.dark ? 0.06 : 0.7),
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: value
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented gel control (e.g. Blue / Graphite).
class AquaSegmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  const AquaSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Ds.radiusM),
          border: Border.all(color: a.gelBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: a.dark ? 0.06 : 0.7),
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Ds.radiusM - 1),
          child: Row(
            children: [
              for (int i = 0; i < labels.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(i),
                    child: AnimatedContainer(
                      duration: Ds.fast,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: Aqua.gel(
                          i == selected ? a.gelBlue : a.gelGray,
                        ),
                        border: i == 0
                            ? null
                            : Border(left: BorderSide(color: a.gelBorder)),
                      ),
                      child: Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: i == selected ? Colors.white : a.glyph,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inset search field with a magnifier, as in iTunes' toolbar. Tappable
/// (it opens the search screen) rather than editable.
class AquaSearchField extends StatelessWidget {
  final VoidCallback onTap;
  final String hint;

  const AquaSearchField({super.key, required this.onTap, this.hint = "Search"});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Semantics(
      button: true,
      label: hint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: a.gelBorder),
                // Inset look: darker rim fading into the field.
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: a.dark
                      ? const [Color(0xFF0C0C0C), Color(0xFF222222)]
                      : const [Color(0xFFD6D6D6), Color(0xFFFFFFFF)],
                  stops: const [0.0, 0.4],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: a.dark ? 0.06 : 0.7),
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 18, color: a.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    hint,
                    style: TextStyle(fontSize: 13.5, color: a.textSecondary),
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

/// Inset "LCD" panel that holds the now-playing info.
class AquaLcd extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AquaLcd({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: a.lcd,
        ),
        borderRadius: BorderRadius.circular(Ds.radiusM),
        border: Border.all(color: a.lcdBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: a.dark ? 0.06 : 0.7),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Thin progress track with a gel-blue fill and a small knob (display only).
class AquaScrubber extends StatelessWidget {
  final double value; // 0..1

  const AquaScrubber({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    final v = value.clamp(0.0, 1.0);

    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          const knob = 11.0;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: a.gelBorder, width: 0.8),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: a.dark
                        ? const [Color(0xFF0F0F0F), Color(0xFF3A3A3A)]
                        : const [Color(0xFF9E9E9E), Color(0xFFE2E2E2)],
                  ),
                ),
              ),
              Container(
                width: (w - knob) * v + knob / 2,
                height: 5,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: Aqua.gel(a.gelBlue),
                ),
              ),
              Positioned(
                left: (w - knob) * v,
                child: Container(
                  width: knob,
                  height: knob,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: Aqua.gel(a.gelGray),
                    border: Border.all(color: a.gelBorder),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Table / group header bar (gradient strip with an optional trailing
/// action), used for list section titles.
class AquaSectionBar extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const AquaSectionBar({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: a.header,
        ),
        border: Border(
          top: BorderSide(color: a.headerBorder),
          bottom: BorderSide(color: a.headerBorder),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: a.text,
                shadows: [
                  Shadow(
                    color: Colors.white.withValues(alpha: a.dark ? 0.0 : 0.8),
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// White-bordered "photo" frame with a drop shadow (iPhoto / Cover Flow).
class AquaPhotoFrame extends StatelessWidget {
  final Widget child;
  final bool circular;

  const AquaPhotoFrame({super.key, required this.child, this.circular = false});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: a.frame,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(3),
        border: Border.all(color: a.frameBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: circular
          ? ClipOval(child: child)
          : ClipRRect(borderRadius: BorderRadius.circular(1.5), child: child),
    );
  }
}

/// Bold group label above a [InsetGroup] (System Preferences style).
class GroupHeader extends StatelessWidget {
  final String title;

  const GroupHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Text(
        title,
        style: TextStyle(
          color: a.text,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          shadows: [
            Shadow(
              color: Colors.white.withValues(alpha: a.dark ? 0.0 : 0.8),
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bordered group box whose rows alternate between white and light blue
/// stripes, like an iTunes table.
class InsetGroup extends StatelessWidget {
  final List<Widget> children;
  final double dividerIndent;

  const InsetGroup({super.key, required this.children, this.dividerIndent = 0});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Container(
      decoration: BoxDecoration(
        color: a.background,
        borderRadius: BorderRadius.circular(Ds.radiusM),
        border: Border.all(color: a.border),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: a.dark ? 0.05 : 0.8),
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++)
            ColoredBox(
              color: i.isEven ? a.background : a.stripe,
              child: children[i],
            ),
        ],
      ),
    );
  }
}

/// Small glossy icon tile (split-gloss gel in the given color).
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    Color shade(double l) =>
        hsl.withLightness((hsl.lightness + l).clamp(0.0, 1.0)).toColor();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: Aqua.gel([
          shade(0.2),
          shade(0.08),
          shade(-0.06),
          shade(0.05),
        ]),
        border: Border.all(color: shade(-0.22)),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.6),
    );
  }
}
