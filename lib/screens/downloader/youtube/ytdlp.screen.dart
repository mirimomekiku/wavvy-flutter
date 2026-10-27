import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/screens/downloader/downloader_dialogs.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/floating_app_bar.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YtdlpSearchScreen extends ConsumerWidget {
  const YtdlpSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            FloatingAppBar(
              title: "YouTube Downloader",
              showSearch: false,
              leading: GelButton(
                circular: true,
                tooltip: "Back",
                onPressed: () => AppNav.pop(),
                child: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: _AquaTabs(labels: ["Search", "Downloads"]),
            ),
            Expanded(
              child: TabBarView(
                children: [_buildSearchView(ref), _buildDownloadsView(ref)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SEARCH TAB ---
  Widget _buildSearchView(WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: _InsetTextField(
            hint: 'Search YouTube...',
            icon: Icons.search_rounded,
            onSubmitted: ref
                .read(ytdlpProvider.notifier)
                .search, // Calls YoutubeExplode search client
          ),
        ),
        Expanded(
          child: Consumer(builder: (context, ref, _) {
            final results = ref.watch(ytdlpProvider.select((s) => s.results));
            if (results.isEmpty) {
              return Builder(
                builder: (context) => Center(
                  child: Text(
                    "Start searching for music",
                    style: TextStyle(color: Aqua.of(context).textSecondary),
                  ),
                ),
              );
            }
            return ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final a = Aqua.of(context);
                final Video video = results[index];
                return ColoredBox(
                  color: index.isEven ? a.background : a.stripe,
                  child: InkWell(
                    onTap: () => showYoutubeDownloadDialog(
                      ref,
                      video,
                    ), // Opens quality selector
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: a.frameBorder),
                              ),
                              child: Image.network(
                                video.thumbnails.lowResUrl,
                                width: 60,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    video.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: a.text,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    video.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: a.textSecondary,
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
              },
            );
          }),
        ),
      ],
    );
  }

  // --- DOWNLOADS TAB ---
  Widget _buildDownloadsView(WidgetRef ref) {
    return Consumer(builder: (context, ref, _) {
      final taskTitles = ref.watch(ytdlpProvider.select((s) => s.taskTitles));
      if (taskTitles.isEmpty) {
        return Builder(
          builder: (context) => Center(
            child: Text(
              "No active downloads",
              style: TextStyle(color: Aqua.of(context).textSecondary),
            ),
          ),
        );
      }

      final taskIds = taskTitles.keys.toList();

      return ListView.builder(
        itemCount: taskIds.length,
        itemBuilder: (context, index) {
          final taskId = taskIds[index];

          return Consumer(builder: (context, ref, _) {
            final a = Aqua.of(context);
            final displayTitle = taskTitles[taskId] ?? "Unknown";
            final progress = ref.watch(
              ytdlpProvider.select((s) => s.progressMap[taskId] ?? 0),
            );
            final status = ref.watch(
              ytdlpProvider.select(
                (s) => s.statusMap[taskId] ?? DownloadTaskStatus.undefined,
              ),
            );

            final isComplete = status == DownloadTaskStatus.complete;

            return ColoredBox(
              color: index.isEven ? a.background : a.stripe,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Row(
                    children: [
                      Icon(
                        isComplete
                            ? Icons.music_note_rounded
                            : Icons.downloading,
                        color: isComplete ? a.accent : a.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: a.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (!isComplete) ...[
                                _GelProgress(value: progress / 100),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                "$progress% - ${_getStatusString(status)}",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: a.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isComplete)
                        GelButton(
                          circular: true,
                          primary: true,
                          tooltip: "Open",
                          onPressed: () {
                            FlutterDownloader.open(taskId: taskId);
                          },
                          child: const Icon(Icons.play_arrow_rounded),
                        ),
                      GelButton(
                        circular: true,
                        tooltip: "Delete",
                        onPressed: () => confirmDeleteYoutubeDownload(ref, taskId),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          });
        },
      );
    });
  }

  String _getStatusString(DownloadTaskStatus status) {
    if (status == DownloadTaskStatus.running) return "Downloading";
    if (status == DownloadTaskStatus.paused) return "Paused";
    if (status == DownloadTaskStatus.complete) return "Done";
    if (status == DownloadTaskStatus.failed) return "Failed";
    return "Pending";
  }
}

/// Segmented gel control bound to the surrounding [DefaultTabController].
class _AquaTabs extends StatelessWidget {
  final List<String> labels;

  const _AquaTabs({required this.labels});

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => AquaSegmented(
        labels: labels,
        selected: controller.index,
        onChanged: controller.animateTo,
      ),
    );
  }
}

/// Inset editable text field (same look as the toolbar search field).
class _InsetTextField extends StatelessWidget {
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onSubmitted;

  const _InsetTextField({
    required this.hint,
    required this.icon,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: a.gelBorder),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: a.dark
              ? const [Color(0xFF0C0C0C), Color(0xFF222222)]
              : const [Color(0xFFD6D6D6), Color(0xFFFFFFFF)],
          stops: const [0.0, 0.4],
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: a.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              style: TextStyle(fontSize: 14, color: a.text),
              cursorColor: a.accent,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14, color: a.textSecondary),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onSubmitted: onSubmitted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim gel progress bar: bordered track with a blue gel fill.
class _GelProgress extends StatelessWidget {
  final double value;

  const _GelProgress({required this.value});

  @override
  Widget build(BuildContext context) {
    final a = Aqua.of(context);
    final v = value.clamp(0.0, 1.0);

    return Container(
      height: 8,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: a.gelBorder, width: 0.8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: a.dark
              ? const [Color(0xFF0F0F0F), Color(0xFF3A3A3A)]
              : const [Color(0xFF9E9E9E), Color(0xFFE2E2E2)],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: Aqua.gel(a.gelBlue)),
            ),
          ),
        ),
      ),
    );
  }
}
