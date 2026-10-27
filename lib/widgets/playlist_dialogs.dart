import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Playlist dialogs / sheets (ported from the old PlaylistsController).

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
    final a = Aqua.of(context);
    return AquaDialog(
      title: "New Playlist",
      content: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Ds.radiusS),
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
        child: TextField(
          controller: _textController,
          autofocus: true,
          style: TextStyle(fontSize: 14, color: a.text),
          cursorColor: a.accent,
          decoration: const InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
      actions: [
        aquaDialogButton("Cancel", () => Navigator.of(context).pop()),
        aquaDialogButton("Create", () {
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
    builder: (context) => AquaDialog(
      title: "Delete Playlist",
      content: Text('Delete "$name"? The songs stay on your device.'),
      actions: [
        aquaDialogButton("Cancel", () => Navigator.of(context).pop()),
        aquaDialogButton("Delete", () async {
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
    builder: (context) => AquaDialog(
      title: "Remove Song",
      content: const Text("Remove this song from the playlist?"),
      actions: [
        aquaDialogButton("Cancel", () => Navigator.of(context).pop()),
        aquaDialogButton("Remove", () async {
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
      final a = Aqua.of(sheetContext);
      return Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AquaSectionBar(title: "Add to Playlist"),
            Expanded(
              child: Consumer(
                builder: (context, ref, child) {
                  final playlists = ref.watch(
                    playlistsProvider.select((s) => s.playlists),
                  );
                  if (playlists.isEmpty) {
                    return Center(
                      child: Text(
                        "No playlists found",
                        style: TextStyle(color: a.textSecondary),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return ColoredBox(
                        color: index.isEven ? a.background : a.stripe,
                        child: ListTile(
                          leading: Icon(Icons.queue_music, color: a.glyph),
                          title: Text(
                            playlist['name'],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: a.text,
                            ),
                          ),
                          onTap: () {
                            ref
                                .read(playlistsProvider.notifier)
                                .addSongToLocalPlaylist(playlist['id'], song.id);
                            Navigator.pop(context);
                          },
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
