import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:wavvy/providers/album_art_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

/// Colors taken from the current song's album art.
class PaletteState {
  /// Dominant artwork color. Null = use the theme.
  final Color? playerColor;
  final Color playerTextColor;

  /// Saturated swatch that drives the app-wide accent when Album colors is on.
  /// Null = the selected appearance's own accent.
  final Color? accent;

  const PaletteState({
    this.playerColor,
    this.playerTextColor = Colors.white,
    this.accent,
  });
}

final paletteProvider = NotifierProvider<PaletteNotifier, PaletteState>(
  PaletteNotifier.new,
);

/// Extracts the artwork palette for the playing song. Results that arrive
/// after the song has changed are ignored.
class PaletteNotifier extends Notifier<PaletteState> {
  @override
  PaletteState build() => const PaletteState();

  /// Album colors off: clears the palette. On: reads the artwork (512px JPEG),
  /// takes dominant / dark-muted / vibrant for [PaletteState.playerColor] and a
  /// saturated swatch for [PaletteState.accent]. No artwork: grey, no accent.
  Future<void> updateForSong(int songId) async {
    // Skip results that arrive after the song has already changed.
    bool isStale() => ref.read(playerProvider).currentSong?.id != songId;
    bool dynamicOn() => ref.read(settingsProvider).enableDynamicColors;

    if (!dynamicOn()) {
      clear();
      return;
    }
    // A file opened from outside the library (negative id) has no MediaStore
    // artwork to read.
    if (songId < 0) {
      clear();
      return;
    }

    try {
      Uint8List? bytes = await ref
          .read(audioQueryProvider)
          .queryArtwork(
            songId,
            ArtworkType.AUDIO,
            format: ArtworkFormat.JPEG,
            // The palette only needs the broad colors.
            size: 200,
          );
      // No embedded art: a fetched cover (see album_art_provider.dart).
      if (bytes == null || bytes.isEmpty) {
        bytes = await cachedArtThumbForSong(ref, songId);
      }
      if (isStale() || !dynamicOn()) return;

      if (bytes == null) {
        state = const PaletteState(
          playerColor: Colors.grey,
          playerTextColor: Colors.white,
          accent: null,
        );
        return;
      }

      final PaletteGenerator palette = await PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        maximumColorCount: 8,
      );
      if (isStale() || !dynamicOn()) return;

      // Prefer a saturated swatch for the app accent; fall back to dominant.
      final Color? extractedColor =
          palette.dominantColor?.color ??
          palette.darkMutedColor?.color ??
          palette.vibrantColor?.color;
      final Color? accent =
          palette.vibrantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.darkVibrantColor?.color ??
          extractedColor;

      if (extractedColor != null) {
        state = PaletteState(
          playerColor: extractedColor,
          playerTextColor: extractedColor.computeLuminance() > 0.5
              ? Colors.black
              : Colors.white,
          accent: accent,
        );
      } else {
        clear();
      }
    } catch (e) {
      debugPrint("_updatePalette failed: $e");
      if (isStale()) return;
      clear();
    }
  }

  /// Drops the artwork colors, keeping the text color.
  void clear() {
    state = PaletteState(playerTextColor: state.playerTextColor);
  }
}
