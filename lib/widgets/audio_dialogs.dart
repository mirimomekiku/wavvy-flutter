import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/core/dialogs.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

/// Confirms, then permanently deletes [song] from the device.
void confirmDeleteSong(WidgetRef ref, SongModel song) {
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
  String title = song.title;
  String artist = song.artist ?? "";
  String album = song.album ?? "";
  String year = "";
  String genre = "";

  // Fetch deep metadata (SongModel is fast but limited).
  try {
    final Metadata? metadata = await MetadataGod.readMetadata(file: song.data);
    if (metadata != null) {
      String getVal(String? val, String fallback) =>
          (val == null || val.isEmpty) ? fallback : val;

      title = getVal(metadata.title, title);
      artist = getVal(metadata.artist, artist);
      album = getVal(metadata.album, album);
      year = metadata.year?.toString() ?? "";
      genre = metadata.genre ?? "";
    }
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
    return AquaDialog(
      title: "Edit Tags",
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTagField("Title", _titleCtrl),
            _buildTagField("Artist", _artistCtrl),
            _buildTagField("Album", _albumCtrl),
            _buildTagField("Year", _yearCtrl, isNumber: true),
            _buildTagField("Genre", _genreCtrl),
          ],
        ),
      ),
      actions: [
        aquaDialogButton("Cancel", () => Navigator.of(context).pop()),
        aquaDialogButton(
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

  Widget _buildTagField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
  }) {
    final a = Aqua.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: a.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
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
              controller: controller,
              keyboardType: isNumber ? TextInputType.number : TextInputType.text,
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
        ],
      ),
    );
  }
}

Future<void> _saveTags(
  WidgetRef ref, {
  required SongModel song,
  required _TagValues values,
}) async {
  try {
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
    await ref.read(libraryProvider.notifier).fetchAllSongs();

    // 5. Keep the player's copy of the song in sync with the new tags.
    final refreshed = ref
        .read(libraryProvider)
        .songs
        .where((s) => s.id == song.id);
    if (refreshed.isNotEmpty) {
      ref.read(playerProvider.notifier).replaceSong(refreshed.first);
    }

    AppSnackbar.showSnackbar("Success", "Tags updated successfully");
  } catch (e) {
    AppSnackbar.showErrorSnackBar(
      "Error",
      "Could not write tags. Permission denied or file read-only.",
    );
  }
}

/// Sleep timer picker.
void openSleepTimerDialog(WidgetRef ref) {
  const options = [15, 30, 45, 60, 90];
  showAppDialog<void>(
    builder: (dialogContext) => Consumer(
      builder: (context, ref, _) {
        final a = Aqua.of(context);
        final current = ref.watch(
          playerProvider.select((s) => s.sleepTimerMinutes),
        );
        return AquaDialog(
          title: "Sleep Timer",
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < options.length; i++)
                  ColoredBox(
                    color: i.isEven ? a.background : a.stripe,
                    child: ListTile(
                      title: Text(
                        "${options[i]} minutes",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: a.text,
                        ),
                      ),
                      trailing: current == options[i]
                          ? Icon(Icons.check, color: a.accent)
                          : null,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        ref
                            .read(playerProvider.notifier)
                            .setSleepTimer(options[i]);
                      },
                    ),
                  ),
                ColoredBox(
                  color: options.length.isEven ? a.background : a.stripe,
                  child: ListTile(
                    title: Text(
                      "Turn Off Timer",
                      style: TextStyle(color: a.textSecondary),
                    ),
                    leading: Icon(
                      Icons.timer_off_outlined,
                      color: a.textSecondary,
                    ),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      ref.read(playerProvider.notifier).setSleepTimer(null);
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            aquaDialogButton("Cancel", () => Navigator.of(dialogContext).pop()),
          ],
        );
      },
    ),
  );
}
