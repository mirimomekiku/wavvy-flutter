import 'package:flutter/material.dart';

/// One line of text that scrolls back and forth when it does not fit, like the
/// text of a portable player. With reduced motion, or when its page is not
/// showing, it is a plain line with an ellipsis. Only one translated text is
/// animated (inside its own layer), and the ticker runs only while the text
/// really is too long.
class CdMarquee extends StatefulWidget {
  const CdMarquee({
    super.key,
    required this.text,
    required this.style,
    this.onTap,
  });
  final String text;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  State<CdMarquee> createState() => _CdMarqueeState();
}

class _CdMarqueeState extends State<CdMarquee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scroll = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );
  bool _running = false;

  /// Starts or stops the ticker once the frame is built (the decision is made
  /// while laying out).
  void _run(bool run) {
    if (run == _running) return;
    _running = run;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _running != run) return;
      if (run) {
        _scroll.repeat(reverse: true);
      } else {
        _scroll
          ..stop()
          ..value = 0;
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final canMove =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: LayoutBuilder(
        builder: (context, c) {
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          final height = painter.height;
          painter.dispose();
          final overflow = c.hasBoundedWidth ? width - c.maxWidth : 0.0;
          if (overflow <= 0.5 || !canMove) {
            _run(false);
            return Text(
              widget.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            );
          }
          _run(true);
          return SizedBox(
            height: height,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _scroll,
                builder: (context, child) {
                  // Rest a moment at each end, then glide to the other.
                  final t = ((_scroll.value - 0.15) / 0.7).clamp(0.0, 1.0);
                  return Transform.translate(
                    offset: Offset(
                      -overflow * Curves.easeInOut.transform(t),
                      0,
                    ),
                    child: child,
                  );
                },
                child: RepaintBoundary(
                  child: OverflowBox(
                    alignment: AlignmentDirectional.centerStart,
                    minWidth: 0,
                    maxWidth: width + 2,
                    child: Text(
                      widget.text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: style,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
