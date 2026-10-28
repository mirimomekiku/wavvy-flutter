import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
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
) => showAddSongsToPlaylistSheet(context, ref, [song]);

/// The playlist picker for one or several songs.
void showAddSongsToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<SongModel> songs, {
  VoidCallback? onAdded,
}) {
  showAquaSheet<void>(
    context: context,
    title: 'Add to Playlist',
    subtitle: songs.length == 1 ? songs.first.title : '${songs.length} songs',
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final playlists = ref.watch(
          playlistsProvider.select((s) => s.playlists),
        );
        return ListView(
          shrinkWrap: true,
          padding: EdgeInsets.only(
            top: 12,
            bottom: 12 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
          children: [
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: AquaEmptyState(
                  icon: Icons.queue_music_rounded,
                  title: 'No playlists yet',
                  hint: 'Create one to start collecting songs.',
                ),
              )
            else
              AquaMenuGroup(
                rows: [
                  for (final playlist in playlists)
                    AquaMenuRow(
                      icon: Icons.queue_music_rounded,
                      label: '${playlist['name']}',
                      onTap: () {
                        final notifier = ref.read(playlistsProvider.notifier);
                        if (songs.length == 1) {
                          notifier.addSongToLocalPlaylist(
                            playlist['id'],
                            songs.first.id,
                          );
                        } else {
                          notifier.addSongsToLocalPlaylist(playlist['id'], [
                            for (final s in songs) s.id,
                          ]);
                        }
                        Navigator.pop(sheetContext);
                        onAdded?.call();
                      },
                    ),
                ],
              ),
            AquaMenuGroup(
              rows: [
                AquaMenuRow(
                  icon: Icons.add_rounded,
                  label: 'New Playlist\u2026',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showNewPlaylistDialog(ref);
                  },
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
    await notifier.addSongsToLocalPlaylist(
      ids.reduce((a, b) => a > b ? a : b),
      [for (final s in widget.songs) s.id],
    );
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return WvDialog(
