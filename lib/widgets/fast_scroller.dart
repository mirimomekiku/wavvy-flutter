import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Accented Latin capitals filed under their base letter.
const _accentLetters = <String, String>{
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A', 'Ā': 'A',
  'Ç': 'C', 'Ć': 'C', 'Č': 'C',
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', 'Ē': 'E', 'Ę': 'E', 'Ě': 'E',
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I', 'Ī': 'I',
  'Ñ': 'N', 'Ń': 'N',
  'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ø': 'O', 'Ō': 'O',
  'Ś': 'S', 'Š': 'S', 'Ş': 'S',
  'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U', 'Ū': 'U',
  'Ý': 'Y', 'Ÿ': 'Y',
  'Ź': 'Z', 'Ż': 'Z', 'Ž': 'Z', //
};

/// The index letter of [text]: A-Z (accents folded, case ignored), or `#` for
/// digits, symbols, other scripts and empty text.
String letterFor(String text) {
  final t = text.trimLeft();
  if (t.isEmpty) return '#';
  final c = String.fromCharCode(t.runes.first).toUpperCase();
  if (c.length == 1) {
    final u = c.codeUnitAt(0);
    if (u >= 65 && u <= 90) return c;
  }
  return _accentLetters[c] ?? '#';
}

/// The item a scroll [fraction] (0 to 1) points at in a list of [count].
int indexForFraction(double fraction, int count) {
  if (count <= 1) return 0;
  return (fraction.clamp(0.0, 1.0) * (count - 1)).round();
}

/// The letter at [fraction], or null when the list has no letters.
String? letterForFraction(
  double fraction,
  int count,
  String Function(int index)? labelAt,
) {
  if (labelAt == null || count <= 0) return null;
  return letterFor(labelAt(indexForFraction(fraction, count)));
}

/// True when the letters of a list never go backwards (`#` first), so a
/// bubble would tell the truth. Used for lists whose order is not ours.
bool lettersAscending(int count, String Function(int index) labelAt) {
  var prev = '#';
  for (var i = 0; i < count; i++) {
    final l = letterFor(labelAt(i));
    if (l.compareTo(prev) < 0) return false;
    prev = l;
  }
  return true;
}

/// A draggable scroll thumb for long lists. It shows while the list scrolls,
/// fades out [hideAfter] after the last interaction and only takes touches in
/// a narrow strip while visible. Dragging scrubs [controller] in proportion to
/// its max extent; with [labelAt] a letter bubble names the item under the
/// thumb. Only the thumb and bubble repaint while dragging, never [child].
class FastScroller extends StatefulWidget {
  const FastScroller({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.child,
    this.labelAt,
    this.trackPadding = EdgeInsets.zero,
    this.minItems = 30,
    this.hideAfter = const Duration(milliseconds: 1200),
  });

  /// The controller of the vertical scroll view inside [child].
  final ScrollController controller;

  /// Items in the list; below [minItems] nothing is drawn.
  final int itemCount;

  /// The text an item is filed under, or null for a plain thumb.
  final String Function(int index)? labelAt;

  /// Keeps the thumb off pinned headers and floating bars.
  final EdgeInsets trackPadding;
  final int minItems;
  final Duration hideAfter;
  final Widget child;

  @override
  State<FastScroller> createState() => _FastScrollerState();
}

class _FastScrollerState extends State<FastScroller> {
  static const _thumbHeight = 56.0;
  static const _strip = 28.0;

  final _fraction = ValueNotifier<double>(0);
  final _visible = ValueNotifier<bool>(false);
  final _dragging = ValueNotifier<bool>(false);
  final _letter = ValueNotifier<String?>(null);
  Timer? _hide;
  double _travel = 0;

  bool get _enabled => widget.itemCount >= widget.minItems;

  @override
  void didUpdateWidget(FastScroller old) {
    super.didUpdateWidget(old);
    if (!_enabled && _visible.value) _visible.value = false;
  }

  @override
  void dispose() {
    _hide?.cancel();
    _fraction.dispose();
    _visible.dispose();
    _dragging.dispose();
    _letter.dispose();
    super.dispose();
  }

  void _hideSoon() {
    _hide?.cancel();
    _hide = Timer(widget.hideAfter, () {
      if (!_dragging.value) _visible.value = false;
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (!_enabled || _dragging.value) return false;
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification && n is! ScrollStartNotification) {
      return false;
    }
    final m = n.metrics;
    if (m.maxScrollExtent <= 0) return false;
    _fraction.value = (m.pixels / m.maxScrollExtent).clamp(0.0, 1.0);
    _visible.value = true;
    _hideSoon();
    return false;
  }

  void _updateLetter(double fraction) {
    final letter = letterForFraction(
      fraction,
      widget.itemCount,
      widget.labelAt,
    );
    if (letter != _letter.value) {
      if (letter != null) HapticFeedback.selectionClick();
      _letter.value = letter;
    }
  }

  void _dragStart(DragStartDetails _) {
    _hide?.cancel();
    _dragging.value = true;
    _visible.value = true;
    _updateLetter(_fraction.value);
  }

  void _dragUpdate(DragUpdateDetails d) {
    final c = widget.controller;
    if (!c.hasClients || _travel <= 0) return;
    final f = (_fraction.value + d.delta.dy / _travel).clamp(0.0, 1.0);
    _fraction.value = f;
    c.jumpTo(f * c.position.maxScrollExtent);
    _updateLetter(f);
  }

  void _dragEnd() {
    _dragging.value = false;
    _letter.value = null;
    _hideSoon();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        if (_enabled)
          Positioned.fill(
            child: Padding(
              padding: widget.trackPadding,
              child: LayoutBuilder(
                builder: (context, box) {
                  _travel = math.max(0, box.maxHeight - _thumbHeight);
                  return ListenableBuilder(
                    listenable: Listenable.merge([
                      _fraction,
                      _visible,
                      _dragging,
                      _letter,
                    ]),
                    builder: (context, _) => _overlay(context),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _overlay(BuildContext context) {
    final a = Wv.of(context);
    final visible = _visible.value;
    final dragging = _dragging.value;
    final top = _fraction.value.clamp(0.0, 1.0) * _travel;
    final letter = _letter.value;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        // A scroll bar is a touch aid: screen readers scroll the list itself.
        child: ExcludeSemantics(
          child: Stack(
            clipBehavior: Clip.none,
            // The bubble goes after the thumb so the thumb keeps its place (and
            // its gesture state) when the bubble comes and goes.
            children: [
              Positioned(
                right: 0,
                top: top,
                width: _strip,
                height: _thumbHeight,
                child: GestureDetector(
                  key: const Key('fast_scroller_thumb'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: _dragStart,
                  onVerticalDragUpdate: _dragUpdate,
                  onVerticalDragEnd: (_) => _dragEnd(),
                  onVerticalDragCancel: _dragEnd,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: dragging ? 10 : 7,
                      height: _thumbHeight - 8,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        gradient: a.gelGradient(primary: dragging),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: a.outline.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (letter != null)
                Positioned(
                  right: _strip + 8,
                  top: top + _thumbHeight / 2 - 30,
                  child: IgnorePointer(
                    child: Container(
                      key: const Key('fast_scroller_bubble'),
                      width: 60,
                      height: 60,
                      alignment: Alignment.center,
                      decoration: a.lcdDecoration.copyWith(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            letter,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: a.text,
                            ),
                          ),
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
