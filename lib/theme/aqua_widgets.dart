import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Mac OS X Aqua building blocks shared by the search fields, switches,
/// pop-up menus and empty states.

/// Capsule frame for a search field: inset top edge, blue focus glow.
/// Put a borderless [TextField] inside.
class AquaSearchFrame extends StatefulWidget {
  const AquaSearchFrame({super.key, required this.child});
  final Widget child;

  @override
  State<AquaSearchFrame> createState() => _AquaSearchFrameState();
}

class _AquaSearchFrameState extends State<AquaSearchFrame> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final fill = a.dark ? const Color(0xFF1B2028) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(fill, Colors.black, a.dark ? 0.35 : 0.1)!, fill],
          stops: const [0, 0.4],
        ),
        border: Border.all(
          color: _focused ? a.accent : a.outline.withValues(alpha: 0.75),
        ),
        boxShadow: [
          if (_focused)
            BoxShadow(
              color: a.accent.withValues(alpha: 0.45),
              blurRadius: 6,
              spreadRadius: 1,
            )
          else
            BoxShadow(
              color: Colors.white.withValues(alpha: a.dark ? 0.05 : 0.8),
              offset: const Offset(0, 1),
            ),
        ],
      ),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: widget.child,
      ),
    );
  }
}

/// Borderless decoration for a [TextField] inside [AquaSearchFrame].
InputDecoration aquaSearchDecoration(
  BuildContext context, {
  required String hint,
  Widget? prefix,
  Widget? suffix,
}) {
  final a = Wv.of(context);
  return InputDecoration(
    isDense: true,
    filled: false,
    contentPadding: const EdgeInsets.symmetric(vertical: 11),
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    hintText: hint,
    hintStyle: TextStyle(fontSize: 14, color: a.textSecondary),
    prefixIcon: prefix,
    suffixIcon: suffix,
  );
}

/// Aqua on/off switch: a gel capsule track (blue when on) and a glossy knob.
class AquaSwitch extends StatelessWidget {
  const AquaSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final enabled = onChanged != null;
    final edge = value
        ? Color.lerp(a.accent, Colors.black, 0.25)!
        : a.outline.withValues(alpha: 0.85);
    final offTrack = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: a.dark
          ? const [Color(0xFF232930), Color(0xFF3A414B)]
          : const [Color(0xFFAEB6C1), Color(0xFFE6EAF0)],
    );
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 50,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: value ? a.gelGradient(primary: true) : offTrack,
                border: Border.all(color: edge),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: a.dark ? 0.05 : 0.7),
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Color(0xFFD5DAE2)],
                    ),
                    border: Border.all(color: a.outline.withValues(alpha: 0.7)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A glossy gel gradient in [base], like [WvPalette.gelGradient] for any color.
LinearGradient aquaGel(Color base) => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color.lerp(base, Colors.white, 0.48)!,
    Color.lerp(base, Colors.white, 0.12)!,
    base,
    Color.lerp(base, Colors.white, 0.13)!,
  ],
  stops: const [0, 0.45, 0.52, 1],
);

/// Glossy gel orb with an icon: the Aqua "button" used by empty states, toasts
/// and the check mark. [color] defaults to the theme's accent.
class AquaOrb extends StatelessWidget {
  const AquaOrb({super.key, required this.icon, this.size = 76, this.color});
  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final base = color ?? a.accent;
    final small = size < 30;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: aquaGel(base),
                border: Border.all(
                  color: Color.lerp(base, Colors.black, 0.28)!,
                ),
                boxShadow: [
                  BoxShadow(
                    color: base.withValues(alpha: 0.35),
                    blurRadius: small ? 5 : 14,
                    offset: Offset(0, small ? 1.5 : 4),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: size * 0.06,
            left: size * 0.16,
            right: size * 0.16,
            height: size * 0.4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.7),
                    Colors.white.withValues(alpha: 0.05),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Icon(
              icon,
              size: size * (small ? 0.62 : 0.44),
              color: Colors.white,
              shadows: const [
                Shadow(color: Color(0x66000000), offset: Offset(0, -1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The Aqua check mark: a blue gel orb with a white tick, in place of a flat
/// check icon.
class AquaCheckMark extends StatelessWidget {
  const AquaCheckMark({super.key, this.size = 24, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Done',
    child: ExcludeSemantics(
      child: AquaOrb(icon: Icons.check_rounded, size: size, color: color),
    ),
  );
}

/// The Aqua activity spinner: twelve spokes with a bright head that moves round
/// in steps, like the Mac OS X progress indicator. Holds still when the system
/// asks for reduced motion.
class AquaSpinner extends StatefulWidget {
  const AquaSpinner({super.key, this.size = 20, this.color});
  final double size;
  final Color? color;

  @override
  State<AquaSpinner> createState() => _AquaSpinnerState();
}

class _AquaSpinnerState extends State<AquaSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 960),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Wv.of(context).textSecondary;
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _SpinnerPainter(
                  color,
                  still ? 0 : (_c.value * 12).floor() % 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.color, this.head);
  final Color color;
  final int head;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, size.shortestSide * 0.1);
    for (var i = 0; i < 12; i++) {
      // 0 for the head, then 1..11 steps behind it.
      final behind = (head - i + 12) % 12;
      paint.color = color.withValues(alpha: 1 - behind / 12 * 0.85);
      final angle = i * math.pi / 6 - math.pi / 2;
      final d = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(c + d * (r * 0.45), c + d * (r * 0.95), paint);
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) =>
      old.head != head || old.color != color;
}

/// Progress as a ring: a groove that fills with blue gel as [value] (0..1)
/// grows, with [child] in the middle. Without a value it is a spinner.
class AquaProgressRing extends StatelessWidget {
  const AquaProgressRing({super.key, this.value, this.size = 38, this.child});
  final double? value;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (value == null)
            AquaSpinner(size: size * 0.85)
          else
            RepaintBoundary(
              child: CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(a, value!.clamp(0.0, 1.0)),
              ),
            ),
          ?child,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.a, this.value);
  final WvPalette a;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.shortestSide * 0.16;
    final rect = (Offset.zero & size).deflate(width / 2 + 1);
    final groove = _grooveDecoration(a);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = groove.gradient!.createShader(Offset.zero & size),
    );
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..shader = a
              .gelGradient(primary: true)
              .createShader(Offset.zero & size),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.a != a;
}

/// The kinds of toast: which icon the orb carries and its color.
enum ToastKind { info, success, error }

/// A toast, as a Mac OS X heads-up display: a dark glossy panel with a gel orb
/// for the icon, the title in white and a line of detail under it.
class AquaToast extends StatelessWidget {
  const AquaToast({
    super.key,
    required this.title,
    this.subtitle = '',
    this.kind = ToastKind.info,
  });
  final String title;
  final String subtitle;
  final ToastKind kind;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final (icon, color) = switch (kind) {
      ToastKind.success => (Icons.check_rounded, a.accent),
      ToastKind.error => (Icons.priority_high_rounded, const Color(0xFFD8453B)),
      ToastKind.info => (Icons.info_outline_rounded, a.accent),
    };
    const radius = 14.0;
    return Semantics(
      liveRegion: true,
      container: true,
      label: subtitle.isEmpty ? title : '$title. $subtitle',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xEB3A3F47), Color(0xEB24272D)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - 1),
            child: Stack(
              children: [
                // The glassy highlight across the top half.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.16),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
                  child: Row(
                    children: [
                      AquaOrb(icon: icon, size: 34, color: color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    color: Color(0x80000000),
                                    offset: Offset(0, -1),
                                  ),
                                ],
                              ),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  fontSize: 12.5,
                                  height: 1.3,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An Aqua empty state: orb, title and an optional hint line and action.
class AquaEmptyState extends StatelessWidget {
  const AquaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });
  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AquaOrb(icon: icon),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: a.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: a.textSecondary,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

/// Face of an Aqua pop-up button: gel capsule with the current value and a
/// blue up/down cap. Use as the child of a [PopupMenuButton] styled with
/// [aquaMenuShape].
class AquaPopupLabel extends StatelessWidget {
  const AquaPopupLabel({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.fromLTRB(12, 0, 3, 0),
      decoration: BoxDecoration(
        gradient: a.gelGradient(),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: a.outline.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: a.dark ? 0.25 : 0.14),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: a.textSecondary),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: a.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 22,
            height: 26,
            decoration: BoxDecoration(
              gradient: a.gelGradient(primary: true),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: Color.lerp(a.accent, Colors.black, 0.25)!,
              ),
            ),
            child: Icon(Icons.unfold_more_rounded, size: 16, color: a.onAccent),
          ),
        ],
      ),
    );
  }
}

/// Menu surface for Aqua pop-up buttons.
ShapeBorder aquaMenuShape(WvPalette a) => RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(8),
  side: BorderSide(color: a.outline.withValues(alpha: 0.7)),
);

/// A Mac OS X window: silver title bar over paper content. Home is made of
/// these. [action] adds a small text button at the right of the title bar.
class AquaWindow extends StatelessWidget {
  const AquaWindow({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.onAction,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 14),
    this.padding = EdgeInsets.zero,
  });
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: a.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: a.outline.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: a.dark ? 0.3 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 34),
                padding: EdgeInsets.fromLTRB(12, 4, action == null ? 12 : 4, 4),
                decoration: BoxDecoration(
                  gradient: a.chromeGradient,
                  image: a.chromeGrain,
                  border: Border(
                    bottom: BorderSide(
                      color: a.outline.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: a.text,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: a.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (action != null)
                      TextButton(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          textStyle: const TextStyle(
                            fontFamily: 'WorkSans',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: Text(action!),
                      ),
                  ],
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// One cell of a recessed LCD readout: a value over a small label.
class AquaLcdCell extends StatelessWidget {
  const AquaLcdCell({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return DecoratedBox(
      decoration: a.lcdDecoration,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: a.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                  color: a.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- Sheets

/// Shows a Mac OS X style sheet from the bottom: a silver title bar with a
/// close button over a paper body. [builder] returns the body, which may be
/// scrollable (it is given the space left under the title bar).
Future<T?> showAquaSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  String? subtitle,
  bool fullScreen = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    // A full-screen sheet draws behind the status bar and pads its own title.
    useSafeArea: !fullScreen,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (sheetContext) => AquaSheet(
      title: title,
      subtitle: subtitle,
      fullScreen: fullScreen,
      child: Builder(builder: builder),
    ),
  );
}

class AquaSheet extends StatelessWidget {
  const AquaSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.fullScreen = false,
  });
  final String title;
  final String? subtitle;
  final Widget child;

  /// Fills the whole screen, status bar included, with square top corners.
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final size = MediaQuery.sizeOf(context);
    final maxHeight = fullScreen ? size.height : size.height * 0.86;
    // The modal route strips the top inset from MediaQuery, so read the window.
    final statusBar = fullScreen
        ? math.max(
            MediaQuery.paddingOf(context).top,
            MediaQueryData.fromView(View.of(context)).padding.top,
          )
        : 0.0;
    final radius = fullScreen ? Radius.zero : const Radius.circular(12);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: a.surface,
        borderRadius: BorderRadius.vertical(top: radius),
        border: Border.all(color: a.outline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: radius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: BoxConstraints(minHeight: 44 + statusBar),
              padding: EdgeInsets.fromLTRB(4, statusBar, 4, 0),
              decoration: BoxDecoration(
                gradient: a.chromeGradient,
                image: a.chromeGrain,
                border: Border(
                  bottom: BorderSide(color: a.outline.withValues(alpha: 0.6)),
                ),
              ),
              child: Row(
                children: [
                  // The red close light; the whole 44px cell is tappable.
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: InkResponse(
                      onTap: () => Navigator.of(context).maybePop(),
                      radius: 22,
                      child: const SizedBox.square(
                        dimension: 44,
                        child: Center(child: AquaCloseLight()),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: a.text,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: a.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Balances the close light so the title stays centered.
                  const SizedBox(width: 44),
                ],
              ),
            ),
            fullScreen ? Expanded(child: child) : Flexible(child: child),
          ],
        ),
      ),
    );
    return fullScreen
        ? SizedBox(height: maxHeight, child: content)
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: content,
          );
  }
}

/// The red close light of an Aqua window title bar (decorative unless wrapped
/// in a tap target).
class AquaCloseLight extends StatelessWidget {
  const AquaCloseLight({super.key});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFFF5F57);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.5),
          colors: [Color.lerp(red, Colors.white, 0.55)!, red],
        ),
        border: Border.all(
          color: Color.lerp(red, Colors.black, 0.35)!,
          width: 0.8,
        ),
      ),
    );
  }
}

/// Menu rows with pale blue striping and hairlines, borderless: for use inside
/// a window or other container. See [AquaMenuGroup] for the bordered version.
class AquaMenuList extends StatelessWidget {
  const AquaMenuList({super.key, required this.rows});
  final List<AquaMenuRow> rows;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: a.separator),
          ColoredBox(color: i.isOdd ? a.stripe : a.surface, child: rows[i]),
        ],
      ],
    );
  }
}

/// A bordered group of menu rows, as in a Mac OS X source list.
class AquaMenuGroup extends StatelessWidget {
  const AquaMenuGroup({
    super.key,
    required this.rows,
    this.margin = const EdgeInsets.fromLTRB(14, 0, 14, 12),
  });
  final List<AquaMenuRow> rows;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: a.outline.withValues(alpha: 0.55)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: AquaMenuList(rows: rows),
      ),
    );
  }
}

/// A menu row. While pressed it fills with the blue Aqua selection and turns
/// white, like a highlighted Mac OS X menu item.
class AquaMenuRow extends StatefulWidget {
  const AquaMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.chevron = false,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final bool chevron;

  /// Marks the current choice with a check mark.
  final bool selected;

  @override
  State<AquaMenuRow> createState() => _AquaMenuRowState();
}

class _AquaMenuRowState extends State<AquaMenuRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final rest = widget.destructive ? a.error : a.text;
    final fg = _pressed ? a.onAccent : rest;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Ink(
            decoration: _pressed
                ? BoxDecoration(gradient: a.gelGradient(primary: true))
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: 20,
                      color: _pressed
                          ? a.onAccent
                          : widget.destructive
                          ? a.error
                          : a.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: fg,
                        ),
                      ),
                    ),
                    if (widget.selected)
                      Icon(
                        Icons.check_rounded,
                        size: 20,
                        color: _pressed ? a.onAccent : a.accent,
                      ),
                    if (widget.chevron)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: _pressed ? a.onAccent : a.textSecondary,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Sliders

/// A horizontal Aqua slider: a recessed groove that fills with blue gel up to a
/// glossy knob.
class AquaSlider extends StatelessWidget {
  const AquaSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
  });
  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 9,
        trackShape: _AquaTrackShape(a),
        thumbShape: _AquaThumbShape(a),
        overlayShape: SliderComponentShape.noOverlay,
        tickMarkShape: SliderTickMarkShape.noTickMark,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }
}

BoxDecoration _grooveDecoration(WvPalette a, {double radius = 5}) =>
    BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: a.dark
            ? const [Color(0xFF12171D), Color(0xFF222B33)]
            : const [Color(0xFFB9C0C6), Color(0xFFE9ECEE)],
      ),
      border: Border.all(
        color: a.dark ? const Color(0xFF0C1014) : const Color(0xFF8C959B),
      ),
    );

class _AquaTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  _AquaTrackShape(this.a);
  final WvPalette a;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final canvas = context.canvas;
    final groove = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.height / 2),
    );
    final deco = _grooveDecoration(a, radius: rect.height / 2);
    final groovePaint = Paint()..shader = deco.gradient!.createShader(rect);
    canvas.drawRRect(groove, groovePaint);

    // The filled part, clipped to the groove.
    final active = Rect.fromLTRB(
      rect.left,
      rect.top,
      thumbCenter.dx,
      rect.bottom,
    );
    canvas.save();
    canvas.clipRRect(groove);
    canvas.drawRect(
      active,
      Paint()
        ..shader = a.gelGradient(primary: true).createShader(rect)
        ..color = Colors.white.withValues(alpha: isEnabled ? 1 : 0.4),
    );
    canvas.restore();
    canvas.drawRRect(
      groove,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (deco.border as Border).top.color,
    );
  }
}

class _AquaThumbShape extends SliderComponentShape {
  _AquaThumbShape(this.a);
  final WvPalette a;
  static const double _size = 22;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(_size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    paintGelKnob(context.canvas, a, center, _size / 2);
  }
}

/// A glossy gel knob (shared by the horizontal and vertical sliders).
void paintGelKnob(Canvas canvas, WvPalette a, Offset center, double radius) {
  final rect = Rect.fromCircle(center: center, radius: radius);
  canvas.drawCircle(
    center.translate(0, 1.5),
    radius,
    Paint()
      ..color = Colors.black.withValues(alpha: a.dark ? 0.5 : 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
  );
  canvas.drawCircle(
    center,
    radius,
    Paint()..shader = a.gelGradient().createShader(rect),
  );
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = a.outline.withValues(alpha: 0.9),
  );
  // A small blue dot in the middle, as on an Aqua scroller grip.
  canvas.drawCircle(center, radius * 0.28, Paint()..color = a.accent);
}

/// A vertical Aqua slider for equalizer bands: a groove that fills with blue
/// gel from the bottom, a centre tick, and a glossy knob. Drag or tap to set.
class AquaVerticalSlider extends StatelessWidget {
  const AquaVerticalSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step,
    this.unit = 'dB',
  });
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  /// How much a screen reader's increase / decrease moves the value.
  final double? step;
  final String unit;

  double _fromDy(double dy, double height) {
    const pad = 11.0;
    final span = height - pad * 2;
    if (span <= 0 || max <= min) return min;
    final t = 1 - ((dy - pad) / span).clamp(0.0, 1.0);
    return min + (max - min) * t;
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final s = step ?? (max - min) / 20;
    final v = value.clamp(min, max);
    String fmt(double x) => '${x.toStringAsFixed(1)} $unit';
    return Semantics(
      slider: true,
      value: fmt(v),
      increasedValue: fmt((v + s).clamp(min, max)),
      decreasedValue: fmt((v - s).clamp(min, max)),
      onIncrease: onChanged == null
          ? null
          : () => onChanged!((v + s).clamp(min, max)),
      onDecrease: onChanged == null
          ? null
          : () => onChanged!((v - s).clamp(min, max)),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.hasBoundedHeight ? c.maxHeight : 180.0;
            void set(double dy) => onChanged?.call(_fromDy(dy, h));
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: onChanged == null
                  ? null
                  : (d) => set(d.localPosition.dy),
              onVerticalDragUpdate: onChanged == null
                  ? null
                  : (d) => set(d.localPosition.dy),
              child: Center(
                child: SizedBox(
                  width: 36,
                  height: h,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _VerticalSliderPainter(
                        a,
                        max > min ? (v - min) / (max - min) : 0,
                        onChanged != null,
                      ),
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

class _VerticalSliderPainter extends CustomPainter {
  _VerticalSliderPainter(this.a, this.fraction, this.enabled);
  final WvPalette a;
  final double fraction;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const pad = 11.0;
    const grooveWidth = 9.0;
    final cx = size.width / 2;
    final groove = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        cx - grooveWidth / 2,
        pad,
        cx + grooveWidth / 2,
        size.height - pad,
      ),
      const Radius.circular(grooveWidth / 2),
    );
    final deco = _grooveDecoration(a, radius: grooveWidth / 2);
    canvas.drawRRect(
      groove,
      Paint()..shader = deco.gradient!.createShader(groove.outerRect),
    );

    final knobY = pad + (size.height - pad * 2) * (1 - fraction);
    canvas.save();
    canvas.clipRRect(groove);
    canvas.drawRect(
      Rect.fromLTRB(groove.left, knobY, groove.right, groove.bottom),
      Paint()
        ..shader = a.gelGradient(primary: true).createShader(groove.outerRect)
        ..color = Colors.white.withValues(alpha: enabled ? 1 : 0.4),
    );
    canvas.restore();
    canvas.drawRRect(
      groove,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = (deco.border as Border).top.color,
    );

    // The middle (0 dB) tick, on both sides of the groove.
    final mid = size.height / 2;
    final tick = Paint()
      ..color = a.textSecondary.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, mid),
      Offset(cx - grooveWidth / 2 - 3, mid),
      tick,
    );
    canvas.drawLine(
      Offset(cx + grooveWidth / 2 + 3, mid),
      Offset(size.width, mid),
      tick,
    );

    paintGelKnob(canvas, a, Offset(cx, knobY), 10);
  }

  @override
  bool shouldRepaint(_VerticalSliderPainter old) =>
      old.fraction != fraction || old.enabled != enabled || old.a != a;
}

/// The Now Playing scrubber: a recessed groove that fills with blue gel up to
/// a glossy knob, like the iTunes progress bar. Tap or drag to seek.
class AquaSeekBar extends StatelessWidget {
  const AquaSeekBar({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.step,
    this.loopStart,
    this.loopEnd,
  });
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// An A-B loop to mark on the bar, in the same units as [value]. A start
  /// without an end shows just the A flag.
  final double? loopStart;
  final double? loopEnd;

  /// How far a screen reader's increase / decrease moves the value.
  final double? step;

  static const double _pad = 11;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final v = value.clamp(0.0, max);
    final s = step ?? max / 20;
    return Semantics(
      slider: true,
      label: 'Seek',
      value: '${(max > 0 ? v / max * 100 : 0).round()}%',
      increasedValue:
          '${(max > 0 ? (v + s).clamp(0.0, max) / max * 100 : 0).round()}%',
      decreasedValue:
          '${(max > 0 ? (v - s).clamp(0.0, max) / max * 100 : 0).round()}%',
      onIncrease: () => onChanged((v + s).clamp(0.0, max)),
      onDecrease: () => onChanged((v - s).clamp(0.0, max)),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth;
            double at(double dx) {
              final span = width - _pad * 2;
              if (span <= 0) return 0;
              return ((dx - _pad) / span).clamp(0.0, 1.0) * max;
            }

            double last = v;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => onChanged(last = at(d.localPosition.dx)),
              onTapUp: (_) => onChangeEnd?.call(last),
              onHorizontalDragUpdate: (d) =>
                  onChanged(last = at(d.localPosition.dx)),
              onHorizontalDragEnd: (_) => onChangeEnd?.call(last),
              child: SizedBox(
                height: 32,
                width: double.infinity,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SeekBarPainter(
                      a,
                      max > 0 ? v / max : 0,
                      max > 0 && loopStart != null
                          ? (loopStart! / max).clamp(0.0, 1.0)
                          : null,
                      max > 0 && loopEnd != null
                          ? (loopEnd! / max).clamp(0.0, 1.0)
                          : null,
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

class _SeekBarPainter extends CustomPainter {
  _SeekBarPainter(this.a, this.fraction, this.loopStart, this.loopEnd);
  final WvPalette a;
  final double fraction;
  final double? loopStart;
  final double? loopEnd;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const pad = AquaSeekBar._pad;
    const grooveHeight = 9.0;
    final cy = size.height / 2;
    final groove = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        pad,
        cy - grooveHeight / 2,
        size.width - pad,
        cy + grooveHeight / 2,
      ),
      const Radius.circular(grooveHeight / 2),
    );
    final deco = _grooveDecoration(a, radius: grooveHeight / 2);
    canvas.drawRRect(
      groove,
      Paint()..shader = deco.gradient!.createShader(groove.outerRect),
    );

    final knobX = pad + (size.width - pad * 2) * fraction;
    canvas.save();
    canvas.clipRRect(groove);
    canvas.drawRect(
      Rect.fromLTRB(groove.left, groove.top, knobX, groove.bottom),
      Paint()
        ..shader = a.gelGradient(primary: true).createShader(groove.outerRect),
    );
    canvas.restore();
    canvas.drawRRect(
      groove,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = (deco.border as Border).top.color,
    );

    // The A-B loop: a band over the groove with a flag at each end.
    double at(double f) => pad + (size.width - pad * 2) * f;
    if (loopStart != null) {
      final flag = Paint()
        ..color = a.accent
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      if (loopEnd != null) {
        canvas.drawRRect(
          RRect.fromLTRBR(
            at(loopStart!),
            cy - grooveHeight / 2 - 2,
            at(loopEnd!),
            cy + grooveHeight / 2 + 2,
            const Radius.circular(3),
          ),
          Paint()..color = a.accent.withValues(alpha: 0.28),
        );
        canvas.drawLine(
          Offset(at(loopEnd!), cy - 9),
          Offset(at(loopEnd!), cy + 9),
          flag,
        );
      }
      canvas.drawLine(
        Offset(at(loopStart!), cy - 9),
        Offset(at(loopStart!), cy + 9),
        flag,
      );
    }
    paintGelKnob(canvas, a, Offset(knobX, cy), 10);
  }

  @override
  bool shouldRepaint(_SeekBarPainter old) =>
      old.fraction != fraction ||
      old.a != a ||
      old.loopStart != loopStart ||
      old.loopEnd != loopEnd;
}

/// A labelled text field with an inset Aqua edge and a blue focus ring.
class AquaField extends StatefulWidget {
  const AquaField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  State<AquaField> createState() => _AquaFieldState();
}

class _AquaFieldState extends State<AquaField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final focused = _focus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: a.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: a.dark ? const Color(0xFF12171D) : Colors.white,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: focused
                  ? a.accent
                  : a.dark
                  ? const Color(0xFF0C1014)
                  : const Color(0xFF8C959B),
              width: focused ? 1.5 : 1,
            ),
            boxShadow: [
              if (focused)
                BoxShadow(
                  color: a.accent.withValues(alpha: 0.4),
                  blurRadius: 5,
                ),
            ],
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            cursorColor: a.accent,
            style: TextStyle(fontSize: 14.5, color: a.text),
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 11,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
