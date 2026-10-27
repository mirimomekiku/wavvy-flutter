import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A section of the current song to repeat: start (A) and end (B).
class AbLoop {
  final Duration? start;
  final Duration? end;

  const AbLoop({this.start, this.end});

  bool get isActive => start != null && end != null;
  bool get isEmpty => start == null && end == null;
}

final abLoopProvider = NotifierProvider<AbLoopNotifier, AbLoop>(
  AbLoopNotifier.new,
);

/// One button, three presses: the first sets A, the second sets B and the
/// section repeats, the third clears it.
class AbLoopNotifier extends Notifier<AbLoop> {
  /// A loop shorter than this is not accepted as B; it is moved to A instead.
  static const minLength = Duration(seconds: 1);

  @override
  AbLoop build() => const AbLoop();

  void press(Duration position) {
    final s = state;
    if (s.isEmpty) {
      state = AbLoop(start: position);
    } else if (!s.isActive) {
      if (position - s.start! < minLength) {
        state = AbLoop(start: position);
      } else {
        state = AbLoop(start: s.start, end: position);
      }
    } else {
      state = const AbLoop();
    }
  }

  void clear() => state = const AbLoop();

  /// Where to jump to when [position] has passed B, or null while inside.
  Duration? jumpFor(Duration position) {
    final s = state;
    if (!s.isActive) return null;
    return position >= s.end! ? s.start : null;
  }
}
