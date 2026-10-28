import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which tab of the full player sheet is showing (0 = player, 1 = queue,
/// 2 = lyrics, 3 = artist, 4 = visualizer, only when its setting is on). The
/// PageController itself lives in the sheet widget's State.
final sheetPageIndexProvider = NotifierProvider<SheetPageIndexNotifier, int>(
  SheetPageIndexNotifier.new,
);

class SheetPageIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}
