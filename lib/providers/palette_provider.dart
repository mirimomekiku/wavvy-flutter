import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:wavvy/core/app_context.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';

/// Album-art colors (replaces AudioController.playerColor /
/// playerTextColor and SettingsService.dynamicAccent).
class PaletteState {
  /// Tint for the player sheet / menus. Null = use theme defaults.
  final Color? playerColor;
  final Color playerTextColor;

  /// Saturated swatch that drives the app-wide Wv accent when Dynamic
  /// Colors is on. Null = default Blue/Graphite.
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

/// Port of AudioController._updatePalette (including the stale-result guard:
/// ignore results if playerProvider's currentSong id != songId by the time
/// artwork/palette finish).
class PaletteNotifier extends Notifier<PaletteState> {
  @override
  PaletteState build() => const PaletteState();

  /// Dynamic colors off: playerColor = theme surfaceContainer, text =
  /// onSurface (use appContext for the theme), accent = null.
  /// On: query artwork (512px JPEG via audioQueryProvider), PaletteGenerator,
  /// playerColor = dominant ?? darkMuted ?? vibrant, text black/white by
  /// luminance, accent = vibrant ?? lightVibrant ?? darkVibrant ?? dominant.
  /// No artwork -> Colors.grey / white text / accent null.
  Future<void> updateForSong(int songId) async {
    // Skip results that arrive after the song has already changed.
    bool isStale() => ref.read(playerProvider).currentSong?.id != songId;
    bool dynamicOn() => ref.read(settingsProvider).enableDynamicColors;

    if (!dynamicOn()) {
      final ctx = appContext;
      final scheme = ctx == null ? null : Theme.of(ctx).colorScheme;
      if (scheme == null) {
        state = PaletteState(
          playerColor: state.playerColor,
          playerTextColor: state.playerTextColor,
          accent: null,
        );
        return;
      }
      state = PaletteState(
        playerColor: scheme.surfaceContainer,
        playerTextColor: scheme.onSurface,
        accent: null,
      );
      return;
    }

    try {
      final Uint8List? bytes = await ref
          .read(audioQueryProvider)
          .queryArtwork(
            songId,
            ArtworkType.AUDIO,
            format: ArtworkFormat.JPEG,
            size: 512,
          );
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

  /// playerColor = null, accent = null.
  void clear() {
    state = PaletteState(playerTextColor: state.playerTextColor);
  }
}
