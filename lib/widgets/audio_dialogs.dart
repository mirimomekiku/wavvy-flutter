import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/core/external_audio.dart';
import 'package:wavvy/core/media_store.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

/// Confirms, then permanently deletes [song] from the device.
void confirmDeleteSong(WidgetRef ref, SongModel song) {
  if (song.isExternal) return;
  showConfirmDialog(
    title: "Delete Song?",
    message:
        "Permanently delete '${song.title}' from your device? This cannot be undone.",
    confirmText: "Delete",
    destructive: true,
    onConfirm: () => ref.read(playerProvider.notifier).deleteSong(song),
  );
}

/// Edit-tags dialog (reads deep metadata with MetadataGod, writes it back).
Future<void> editSongTags(WidgetRef ref, SongModel song) async {
  if (song.isExternal) return;
  String title = song.title;
  String artist = song.artist ?? "";
  String album = song.album ?? "";
  String year = "";
  String genre = "";

  // Fetch deep metadata (SongModel is fast but limited).
  try {
    final metadata = await MetadataGod.readMetadata(file: song.data);
    String getVal(String? val, String fallback) =>
        (val == null || val.isEmpty) ? fallback : val;

    title = getVal(metadata.title, title);
    artist = getVal(metadata.artist, artist);
    album = getVal(metadata.album, album);
    year = metadata.year?.toString() ?? "";
    genre = metadata.genre ?? "";
  } catch (e) {
    debugPrint("readMetadata failed: $e");
  }

  final result = await showAppDialog<_TagValues>(
    builder: (context) => _TagEditorDialog(
      initial: _TagValues(
        title: title,
        artist: artist,
        album: album,
        year: year,
        genre: genre,
      ),
    ),
  );
  if (result == null) return;

  await _saveTags(ref, song: song, values: result);
}

class _TagValues {
  final String title;
  final String artist;
  final String album;
  final String year;
  final String genre;

  const _TagValues({
    required this.title,
    required this.artist,
    required this.album,
    required this.year,
    required this.genre,
  });
}

/// Owns the text controllers so they are disposed with the dialog.
class _TagEditorDialog extends StatefulWidget {
  final _TagValues initial;

  const _TagEditorDialog({required this.initial});

  @override
  State<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<_TagEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _artistCtrl;
  late final TextEditingController _albumCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _genreCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initial.title);
    _artistCtrl = TextEditingController(text: widget.initial.artist);
    _albumCtrl = TextEditingController(text: widget.initial.album);
    _yearCtrl = TextEditingController(text: widget.initial.year);
    _genreCtrl = TextEditingController(text: widget.initial.genre);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _yearCtrl.dispose();
    _genreCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WvDialog(
      title: "Edit Tags",
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AquaField(label: 'Title', controller: _titleCtrl),
            const SizedBox(height: 12),
            AquaField(label: 'Artist', controller: _artistCtrl),
            const SizedBox(height: 12),
            AquaField(label: 'Album', controller: _albumCtrl),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: AquaField(
                    label: 'Year',
                    controller: _yearCtrl,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AquaField(label: 'Genre', controller: _genreCtrl),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        wvDialogButton("Cancel", () => Navigator.of(context).pop()),
        wvDialogButton(
          "Save",
          () => Navigator.of(context).pop(
            _TagValues(
              title: _titleCtrl.text,
              artist: _artistCtrl.text,
              album: _albumCtrl.text,
              year: _yearCtrl.text,
              genre: _genreCtrl.text,
            ),
          ),
          primary: true,
        ),
      ],
    );
  }
}

Future<void> _saveTags(
  WidgetRef ref, {
  required SongModel song,
  required _TagValues values,
}) async {
  try {
    // Android 10+ only lets an app edit a media file after the user agrees.
    final mediaStore = ref.read(mediaStoreProvider);
    final allowed = await mediaStore.requestWriteAccess(song.id);
    if (!allowed) {
      AppSnackbar.showSnackbar(
        "Tags not changed",
        "Allow Wavvy to modify this song to edit its tags.",
      );
      return;
    }

    AppSnackbar.showSnackbar("Saving metadata...", "");

    // 1. Read existing metadata to preserve artwork and other fields
    Metadata? currentMetadata;
    try {
      currentMetadata = await MetadataGod.readMetadata(file: song.data);
    } catch (e) {
      debugPrint("readMetadata failed: $e");
    }

    // 2. Prepare new Metadata, copying picture/track info so it isn't lost
    final newMetadata = Metadata(
      title: values.title,
      artist: values.artist,
      album: values.album,
      year: int.tryParse(values.year),
      genre: values.genre,
      picture: currentMetadata?.picture,
      trackNumber: currentMetadata?.trackNumber,
      discNumber: currentMetadata?.discNumber,
      albumArtist: currentMetadata?.albumArtist,
      durationMs: currentMetadata?.durationMs,
    );

    // 3. Write to file
    await MetadataGod.writeMetadata(file: song.data, metadata: newMetadata);

    // 4. Refresh library
    await mediaStore.scanFile(song.data);
    await ref.read(libraryProvider.notifier).fetchAllSongs();

    // 5. Keep the player's copy of the song in sync with the new tags.
    final refreshed = ref
        .read(libraryProvider)
        .songs
        .where((s) => s.id == song.id);
    if (refreshed.isNotEmpty) {
      ref.read(playerProvider.notifier).replaceSong(refreshed.first);
    }

    AppSnackbar.showSuccess("Success", "Tags updated successfully");
  } catch (e) {
    AppSnackbar.showErrorSnackBar(
      "Error",
      "Could not write tags. Permission denied or file read-only.",
    );
  }
}

/// Sleep timer picker: a menu of durations with the current one checked.
void openSleepTimerDialog(WidgetRef ref) {
  const options = [15, 30, 45, 60, 90];
  const trackOptions = [2, 3, 5];
  showAppDialog<void>(
    builder: (dialogContext) => Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(
          playerProvider.select((s) => s.sleepTimerMinutes),
        );
        final mode = ref.watch(playerProvider.select((s) => s.sleepMode));
        final endsAt = ref.watch(playerProvider.select((s) => s.sleepEndsAt));
        final tracksLeft = ref.watch(
          playerProvider.select((s) => s.sleepTracksLeft),
        );
        final a = Wv.of(context);
        final status = switch (mode) {
          SleepMode.off => 'Music plays until you stop it',
          SleepMode.minutes =>
            endsAt == null
                ? 'Music stops in $current minutes'
                : 'Music stops at ${TimeOfDay.fromDateTime(endsAt).format(context)}',
          SleepMode.endOfTrack => 'Music stops after this track',
          SleepMode.endOfQueue => 'Music stops after the last track',
          SleepMode.afterTracks =>
            (tracksLeft ?? 1) <= 1
                ? 'Music stops after this track'
                : 'Music stops after $tracksLeft more tracks',
        };
        void choose(int? minutes) {
          Navigator.of(dialogContext).pop();
          ref.read(playerProvider.notifier).setSleepTimer(minutes);
        }

        return WvDialog(
          title: "Sleep Timer",
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: a.lcdDecoration.copyWith(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        mode == SleepMode.off
                            ? Icons.timer_off_outlined
                            : Icons.bedtime_rounded,
                        size: 18,
                        color: mode == SleepMode.off
                            ? a.textSecondary
                            : a.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status,
                          style: TextStyle(
                            color: a.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (mode == SleepMode.minutes ||
                    mode == SleepMode.endOfTrack ||
                    mode == SleepMode.afterTracks) ...[
                  AquaMenuGroup(
                    margin: EdgeInsets.zero,
                    rows: [
                      AquaMenuRow(
                        icon: Icons.add_alarm_rounded,
                        label: mode == SleepMode.minutes
                            ? 'Add 10 minutes'
                            : 'Add one more track',
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          ref.read(playerProvider.notifier).extendSleep();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                AquaMenuGroup(
                  margin: EdgeInsets.zero,
                  rows: [
                    for (final m in options)
                      AquaMenuRow(
                        icon: Icons.bedtime_rounded,
                        label: '$m minutes',
                        selected: mode == SleepMode.minutes && current == m,
                        onTap: () => choose(m),
                      ),
                    AquaMenuRow(
                      icon: Icons.music_note_rounded,
                      label: 'End of this track',
                      selected: mode == SleepMode.endOfTrack,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        ref
                            .read(playerProvider.notifier)
                            .setSleepAtEnd(SleepMode.endOfTrack);
                      },
                    ),
                    for (final n in trackOptions)
                      AquaMenuRow(
                        icon: Icons.skip_next_rounded,
                        label: 'After $n tracks',
                        selected:
                            mode == SleepMode.afterTracks && tracksLeft == n,
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          ref
                              .read(playerProvider.notifier)
                              .setSleepAfterTracks(n);
                        },
                      ),
                    AquaMenuRow(
                      icon: Icons.queue_music_rounded,
                      label: 'End of the queue',
                      selected: mode == SleepMode.endOfQueue,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        ref
                            .read(playerProvider.notifier)
                            .setSleepAtEnd(SleepMode.endOfQueue);
                      },
                    ),
                    AquaMenuRow(
                      icon: Icons.timer_off_outlined,
                      label: 'Turn off timer',
                      onTap: () => choose(null),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            wvDialogButton("Cancel", () => Navigator.of(dialogContext).pop()),
          ],
        );
      },
    ),
  );
}
