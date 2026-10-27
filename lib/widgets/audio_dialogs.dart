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
    return WvDialog(
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

  Widget _buildTagField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
  }) {
    final a = Wv.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: a.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            style: TextStyle(fontSize: 15, color: a.text),
            cursorColor: a.accent,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: a.surfaceHighest,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
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
        final current = ref.watch(
          playerProvider.select((s) => s.sleepTimerMinutes),
        );
        return WvDialog(
          title: "Sleep Timer",
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < options.length; i++)
                  _SleepOption(
                    label: "${options[i]} minutes",
                    icon: Icons.bedtime_rounded,
                    selected: current == options[i],
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      ref
                          .read(playerProvider.notifier)
                          .setSleepTimer(options[i]);
                    },
                  ),
                _SleepOption(
                  label: "Turn Off Timer",
                  icon: Icons.timer_off_outlined,
                  selected: false,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    ref.read(playerProvider.notifier).setSleepTimer(null);
                  },
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

/// Tonal squircle option row (the selected one is filled with the primary).
class _SleepOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SleepOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final bg = selected ? a.accent : a.surfaceHighest;
    final fg = selected ? a.onAccent : a.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 24, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_rounded, size: 24, color: fg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
