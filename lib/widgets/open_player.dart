import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/player_sheets/full_player_sheet.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/player_sheet_provider.dart';

void openWavvyPlayer(BuildContext context, WidgetRef ref, {int page = 0}) {
  if (ref.read(playerProvider).currentSong == null) return;
  ref.read(sheetPageIndexProvider.notifier).set(page);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    builder: (_) => FullPlayerSheet(initialPage: page),
  );
}
