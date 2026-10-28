import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/downloader/cover.dart';
import 'package:wavvy/downloader/downloads_provider.dart';
import 'package:wavvy/downloader/models.dart';
import 'package:wavvy/screens/search/library_results.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

/// The selected Downloads view: 0 All, 1 Active, 2 Completed, 3 Failed.
final downloadFilterProvider = NotifierProvider<DownloadFilterNotifier, int>(
  DownloadFilterNotifier.new,
);

class DownloadFilterNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

String _statusText(DownloadTask task) => switch (task.status) {
  DownloadStatus.queued => 'Waiting to start',
  DownloadStatus.running =>
    task.progress > 0 ? '${task.progress}% · Downloading' : 'Starting…',
  DownloadStatus.publishing => 'Adding to your library…',
  DownloadStatus.complete => 'In your library',
  DownloadStatus.failed => task.error.isEmpty ? 'Failed' : task.error,
  DownloadStatus.canceled => 'Canceled',
};

/// The download history as a sliver: filter chips, then one row per download
/// with the actions that make sense for its state.
class DownloadsList extends ConsumerWidget {
  const DownloadsList({super.key, this.query = ''});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final all = ref.watch(downloadsProvider);
    final filter = ref.watch(downloadFilterProvider);
    final q = query.trim().toLowerCase();
    final tasks = all
        .where(
          (t) =>
              (t.title.toLowerCase().contains(q) ||
                  t.artist.toLowerCase().contains(q)) &&
              (filter == 0 ||
                  filter == 1 && t.status.active ||
                  filter == 2 && t.status == DownloadStatus.complete ||
                  filter == 3 &&
                      (t.status == DownloadStatus.failed ||
                          t.status == DownloadStatus.canceled)),
        )
        .toList();
    final notifier = ref.read(downloadsProvider.notifier);

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${all.where((t) => t.status.active).length} active · '
                  '${all.where((t) => t.status == DownloadStatus.complete).length} completed',
                  style: TextStyle(fontSize: 12, color: a.textSecondary),
                ),
                const SizedBox(height: 8),
                WvChips(
                  labels: const ['All', 'Active', 'Completed', 'Failed'],
                  selected: filter,
                  onChanged: (index) =>
                      ref.read(downloadFilterProvider.notifier).set(index),
                ),
              ],
            ),
          ),
        ),
        if (tasks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: SearchEmptyState(
              message: q.isNotEmpty
                  ? 'No matching downloads'
                  : all.isEmpty
                  ? 'No downloads yet'
                  : 'No downloads in this view',
              icon: Icons.download_done_rounded,
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final task = tasks[index];
              final failed = task.status == DownloadStatus.failed;
              final done = task.status == DownloadStatus.complete;
              return Container(
                decoration: BoxDecoration(
                  color: index.isOdd ? a.stripe : a.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: a.separator.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                child: Row(
                  children: [
                    WvArtwork(
                      radius: 7,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: !isAllowedCoverUrl(task.thumbnail)
                            ? Icon(Icons.music_note_rounded, color: a.accent)
                            : Image.network(
                                task.thumbnail,
                                fit: BoxFit.cover,
                                cacheWidth: 144,
                                errorBuilder: (_, _, _) => Icon(
                                  Icons.music_note_rounded,
                                  color: a.accent,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: a.text,
                            ),
                          ),
                          if (task.status.active) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value:
                                    task.status == DownloadStatus.running &&
                                        task.progress > 0
                                    ? task.progress / 100
                                    : null,
                                minHeight: 3,
                              ),
                            ),
                          ],
                          const SizedBox(height: 5),
                          Text(
                            _statusText(task),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: failed ? a.error : a.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (task.status.active)
                      IconButton(
                        tooltip: 'Cancel',
                        onPressed: () => notifier.cancel(task.id),
                        icon: Icon(Icons.close_rounded, color: a.textSecondary),
                      ),
                    if (failed || task.status == DownloadStatus.canceled)
                      IconButton(
                        tooltip: 'Try again',
                        onPressed: () => notifier.retry(task.id),
                        icon: Icon(Icons.refresh_rounded, color: a.accent),
                      ),
                    if (done)
                      IconButton(
                        tooltip: 'Play',
                        onPressed: () async {
                          final ok = await notifier.play(task);
                          if (!ok) {
                            AppSnackbar.showSnackbar(
                              'Not in your library yet',
                              'Pull down on Home to rescan, then try again.',
                            );
                          }
                        },
                        icon: Icon(Icons.play_circle_rounded, color: a.accent),
                      ),
                    if (!task.status.active)
                      PopupMenuButton<String>(
                        tooltip: 'More',
                        icon: Icon(
                          Icons.more_horiz_rounded,
                          color: a.textSecondary,
                        ),
                        color: a.surface,
                        shape: aquaMenuShape(a),
                        onSelected: (value) {
                          if (value == 'remove') {
                            notifier.remove(task.id);
                          } else if (value == 'delete') {
                            showConfirmDialog(
                              title: 'Delete the file?',
                              message:
                                  "'${task.title}' will be deleted from your "
                                  'device. This cannot be undone.',
                              confirmText: 'Delete',
                              destructive: true,
                              onConfirm: () =>
                                  notifier.remove(task.id, deleteFile: true),
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove from list'),
                          ),
                          if (done)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete file…'),
                            ),
                        ],
                      ),
                  ],
                ),
              );
            }, childCount: tasks.length),
          ),
      ],
    );
  }
}
