import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/screens/downloader/downloader_dialogs.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/floating_app_bar.dart';

class TikTokSearchScreen extends ConsumerStatefulWidget {
  const TikTokSearchScreen({super.key});

  @override
  ConsumerState<TikTokSearchScreen> createState() => _TikTokSearchScreenState();
}

class _TikTokSearchScreenState extends ConsumerState<TikTokSearchScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            FloatingAppBar(
              title: "TikTok Downloader",
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
              child: _AquaTabs(labels: ["Paste Link", "Downloads"]),
            ),
            Expanded(
              child: TabBarView(
                children: [_buildSearchView(), _buildDownloadsView()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SEARCH (PASTE LINK) TAB ---
  Widget _buildSearchView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Builder(
            builder: (context) {
              final a = Aqua.of(context);
              return Container(
                height: 48,
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
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
                    Icon(Icons.link_rounded, size: 18, color: a.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: TextStyle(fontSize: 14, color: a.text),
                        cursorColor: a.accent,
                        decoration: InputDecoration(
                          hintText: 'Paste TikTok Link...',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: a.textSecondary,
                          ),
                          isDense: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onSubmitted: (val) =>
                            ref.read(tiktokProvider.notifier).fetchVideoInfo(val),
                      ),
                    ),
                    GelButton(
                      circular: true,
                      primary: true,
                      size: 28,
                      tooltip: "Fetch video",
                      onPressed: () => ref
                          .read(tiktokProvider.notifier)
                          .fetchVideoInfo(_urlController.text),
                      child: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Expanded(
          child: Consumer(builder: (context, ref, _) {
            if (ref.watch(tiktokProvider.select((s) => s.isLoading))) {
              return const Center(child: CircularProgressIndicator());
            }

            final video = ref.watch(
              tiktokProvider.select((s) => s.fetchedVideo),
            );

            // Empty State
            if (video == null) {
              return Builder(
                builder: (context) {
                  final a = Aqua.of(context);
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.copy, size: 64, color: a.textSecondary),
                        const SizedBox(height: 16),
                        Text(
                          "Copy a link from TikTok and paste it here",
                          style: TextStyle(color: a.textSecondary),
                        ),
                      ],
                    ),
                  );
                },
              );
            }

            // Result State (Found Video)
            return Builder(
              builder: (context) {
                final a = Aqua.of(context);
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cover Image
                      if (video['cover'] != null)
                        Center(
                          child: AquaPhotoFrame(
                            child: Image.network(
                              video['cover'],
                              height: 250,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                height: 250,
                                width: 180,
                                color: a.stripe,
                                child: Center(
                                  child: Icon(
                                    Icons.broken_image,
                                    color: a.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        video['title'] ?? "No Title",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: a.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.person, size: 16, color: a.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "@${video['author']}",
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: a.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: GelButton(
                          primary: true,
                          size: 34,
                          width: 190,
                          tooltip: "Download Video",
                          onPressed: () async {
                            final started = await ref
                                .read(tiktokProvider.notifier)
                                .downloadVideo(video);
                            if (started) _urlController.clear();
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download_rounded),
                              SizedBox(width: 6),
                              Text("Download Video"),
                            ],
                          ),
                        ),
                      ),
                    ],
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
  Widget _buildDownloadsView() {
    return Consumer(builder: (context, ref, _) {
      final taskTitles = ref.watch(tiktokProvider.select((s) => s.taskTitles));
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
              tiktokProvider.select((s) => s.progressMap[taskId] ?? 0),
            );
            final status = ref.watch(
              tiktokProvider.select(
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
                        isComplete ? Icons.video_file : Icons.downloading,
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
                          onPressed: () =>
                              FlutterDownloader.open(taskId: taskId),
                          child: const Icon(Icons.play_arrow_rounded),
                        ),
                      GelButton(
                        circular: true,
                        tooltip: "Delete",
                        onPressed: () => confirmDeleteTikTokDownload(ref, taskId),
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
