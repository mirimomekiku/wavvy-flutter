import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Playlist dialogs / sheets (ported from the old PlaylistsController).

InputDecoration _wvFieldDecoration(WvPalette a, String hint) => InputDecoration(
  isDense: true,
  filled: true,
  fillColor: a.surfaceHighest,
  hintText: hint,
  hintStyle: TextStyle(color: a.textSecondary),
  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide.none,
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: a.accent, width: 1.5),
  ),
);

void showNewPlaylistDialog(WidgetRef ref) {
  showAppDialog<void>(builder: (context) => _NewPlaylistDialog(ref: ref));
}

class _NewPlaylistDialog extends StatefulWidget {
  final WidgetRef ref;
  const _NewPlaylistDialog({required this.ref});

  @override
  State<_NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<_NewPlaylistDialog> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return WvDialog(
      title: "New Playlist",
      content: TextField(
        controller: _textController,
        autofocus: true,
        style: TextStyle(fontSize: 15, color: a.text),
        cursorColor: a.accent,
        decoration: _wvFieldDecoration(a, "Playlist name"),
      ),
      actions: [
        wvDialogButton("Cancel", () => Navigator.of(context).pop()),
        wvDialogButton("Create", () {
          widget.ref
              .read(playlistsProvider.notifier)
              .createLocalPlaylist(_textController.text);
          Navigator.of(context).pop();
        }, primary: true),
      ],
    );
  }
}

void showDeletePlaylistDialog(WidgetRef ref, int playlistId, String name) {
  showAppDialog<void>(
    builder: (context) => WvDialog(
      title: "Delete Playlist",
      content: Text('Delete "$name"? The songs stay on your device.'),
      actions: [
        wvDialogButton("Cancel", () => Navigator.of(context).pop()),
        wvDialogButton("Delete", () async {
          await ref
              .read(playlistsProvider.notifier)
              .deleteLocalPlaylist(playlistId);
          AppNav.pop();
        }, destructive: true),
      ],
    ),
  );
}

void showRemoveFromPlaylistDialog(WidgetRef ref, int playlistId, int songId) {
  showAppDialog<void>(
    builder: (context) => WvDialog(
      title: "Remove Song",
      content: const Text("Remove this song from the playlist?"),
      actions: [
        wvDialogButton("Cancel", () => Navigator.of(context).pop()),
        wvDialogButton("Remove", () async {
          await ref
              .read(playlistsProvider.notifier)
              .removeFromLocalPlaylist(playlistId, songId);
          AppNav.pop();
        }, destructive: true),
      ],
    ),
  );
}

void showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  SongModel song,
) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final a = Wv.of(sheetContext);
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: WvSectionHeader(title: "Add to Playlist"),
            ),
            Flexible(
              child: Consumer(
                builder: (context, ref, child) {
                  final playlists = ref.watch(
                    playlistsProvider.select((s) => s.playlists),
                  );
                  if (playlists.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          "No playlists found",
                          style: TextStyle(color: a.textSecondary),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final (bg, fg) = a.tonal(index);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: bg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: a.outline.withValues(alpha: 0.35),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              ref
                                  .read(playlistsProvider.notifier)
                                  .addSongToLocalPlaylist(
                                    playlist['id'],
                                    song.id,
                                  );
                              Navigator.pop(context);
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 60),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.queue_music_rounded,
                                      size: 24,
                                      color: fg,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        playlist['name'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: fg,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
