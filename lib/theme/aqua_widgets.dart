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

/// Glossy gel orb with an icon: the Aqua "button" used by empty states.
class AquaOrb extends StatelessWidget {
  const AquaOrb({super.key, required this.icon, this.size = 76});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: a.gelGradient(primary: true),
                border: Border.all(
                  color: Color.lerp(a.accent, Colors.black, 0.25)!,
                ),
                boxShadow: [
                  BoxShadow(
                    color: a.accent.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
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
              size: size * 0.44,
              color: a.onAccent,
              shadows: const [
                Shadow(color: Color(0x66305792), offset: Offset(0, -1)),
              ],
            ),
          ),
        ],
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
