import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/album_art_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// What the "Find missing artwork" row says about a run, as a short readout
/// ("12 of 48 albums, 9 found"). Pure, so it is easy to test.
String artBatchReadout(ArtBatchState s) {
  final progress = '${s.done} of ${s.total} albums, ${s.found} found';
  switch (s.status) {
    case ArtBatchStatus.idle:
      return 'Look up covers for albums that have none';
    case ArtBatchStatus.scanning:
      return 'Checking your library for albums without a cover...';
    case ArtBatchStatus.running:
      return progress;
    case ArtBatchStatus.done:
      if (s.total == 0) return 'No albums need a cover';
      return 'Done: ${s.found} of ${s.total} albums got a cover';
    case ArtBatchStatus.cancelled:
      return 'Cancelled: $progress';
    case ArtBatchStatus.stopped:
      final why = switch (s.stopReason) {
        ArtFetch.offline => 'no connection',
        ArtFetch.rateLimited => 'the service asked to slow down',
        _ => 'something went wrong',
      };
      return 'Stopped, $why: $progress';
  }
}

/// A Settings row (shown while the setting is on) that looks for covers for
/// every album without one. The run lives in [albumArtBatchProvider], so it
/// goes on when this screen is left; Cancel stops it after the current album.
class FindMissingArtRow extends ConsumerWidget {
  const FindMissingArtRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final s = ref.watch(albumArtBatchProvider);
    final notifier = ref.read(albumArtBatchProvider.notifier);
    return ListTile(
      dense: true,
      onTap: s.active ? null : notifier.startManual,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(
        Icons.image_search_rounded,
        color: a.textSecondary,
        size: 22,
      ),
      title: Text(
        'Find missing artwork',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: a.text,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          artBatchReadout(s),
          style: TextStyle(fontSize: 12, height: 1.4, color: a.textSecondary),
        ),
      ),
      trailing: s.active
          ? TextButton(onPressed: notifier.cancel, child: const Text('Cancel'))
          : const Icon(Icons.chevron_right_rounded),
    );
  }
}
