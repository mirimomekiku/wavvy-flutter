import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/screens/downloader/downloader_dialogs.dart';
import 'package:wavvy/screens/search/library_results.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

final downloadFilterProvider = StateProvider<int>((ref) => 0);

class _Task {
  const _Task(this.tiktok, this.id, this.title, this.progress, this.status);
  final bool tiktok;
  final String id;
  final String title;
  final int progress;
  final DownloadTaskStatus status;
  bool get active =>
      status == DownloadTaskStatus.running ||
      status == DownloadTaskStatus.enqueued ||
      status == DownloadTaskStatus.paused;
}

String _statusText(DownloadTaskStatus status) {
  if (status == DownloadTaskStatus.running) return 'Downloading';
  if (status == DownloadTaskStatus.paused) return 'Paused';
  if (status == DownloadTaskStatus.complete) return 'Done';
  if (status == DownloadTaskStatus.failed) return 'Failed';
  if (status == DownloadTaskStatus.canceled) return 'Canceled';
  return 'Pending';
}

class DownloadsList extends ConsumerWidget {
  const DownloadsList({super.key, this.query = ''});
  final String query;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final yt = ref.watch(ytdlpProvider);
    final tt = ref.watch(tiktokProvider);
    final filter = ref.watch(downloadFilterProvider);
    final all = [
      for (final task in yt.taskTitles.entries)
        _Task(
          false,
          task.key,
          task.value,
          yt.progressMap[task.key] ?? 0,
          yt.statusMap[task.key] ?? DownloadTaskStatus.undefined,
        ),
      for (final task in tt.taskTitles.entries)
        _Task(
          true,
          task.key,
          task.value,
          tt.progressMap[task.key] ?? 0,
          tt.statusMap[task.key] ?? DownloadTaskStatus.undefined,
        ),
    ];
    final tasks = all
        .where(
          (t) =>
              t.title.toLowerCase().contains(query.trim().toLowerCase()) &&
              (filter == 0 ||
                  filter == 1 && t.active ||
                  filter == 2 && t.status == DownloadTaskStatus.complete ||
                  filter == 3 && t.status == DownloadTaskStatus.failed),
        )
        .toList();
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${all.where((t) => t.active).length} active \u00b7 ${all.where((t) => t.status == DownloadTaskStatus.complete).length} completed',
                  style: TextStyle(fontSize: 12, color: a.textSecondary),
                ),
                const SizedBox(height: 8),
                WvChips(
                  labels: const ['All', 'Active', 'Completed', 'Failed'],
                  selected: filter,
                  onChanged: (index) =>
                      ref.read(downloadFilterProvider.notifier).state = index,
                ),
              ],
            ),
          ),
        ),
        if (tasks.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: SearchEmptyState(
              message: query.trim().isNotEmpty
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
              final done = task.status == DownloadTaskStatus.complete;
              final failed = task.status == DownloadTaskStatus.failed;
              return Container(
                decoration: BoxDecoration(
                  color: index.isOdd ? a.stripe : a.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: a.separator.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: a.surfaceHigh,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        failed
                            ? Icons.error_outline_rounded
                            : done
                            ? Icons.check_circle_outline_rounded
                            : Icons.downloading_rounded,
                        color: failed ? a.error : a.accent,
                        size: 22,
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
                          const SizedBox(height: 6),
                          if (!done && !failed) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: task.progress.clamp(0, 100) / 100,
                                minHeight: 3,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            '${task.progress}% \u00b7 ${_statusText(task.status)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: failed ? a.error : a.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (done)
                      IconButton(
                        tooltip: 'Open',
                        onPressed: () =>
                            FlutterDownloader.open(taskId: task.id),
                        icon: Icon(
                          Icons.open_in_new_rounded,
                          size: 20,
                          color: a.accent,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: () => task.tiktok
                          ? confirmDeleteTikTokDownload(ref, task.id)
                          : confirmDeleteYoutubeDownload(ref, task.id),
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: a.textSecondary,
                      ),
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
