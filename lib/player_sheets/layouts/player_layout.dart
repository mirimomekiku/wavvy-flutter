import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/player_sheets/layouts/cover_flow_layout.dart';
import 'package:wavvy/player_sheets/layouts/hifi_layout.dart';
import 'package:wavvy/player_sheets/layouts/itunes_layout.dart';
import 'package:wavvy/player_sheets/layouts/lyrics_first_layout.dart';
import 'package:wavvy/player_sheets/layouts/player_layout_data.dart';
import 'package:wavvy/player_sheets/layouts/poster_layout.dart';
import 'package:wavvy/player_sheets/layouts/two_pane_layout.dart';
import 'package:wavvy/player_sheets/layouts/vinyl_layout.dart';
import 'package:wavvy/providers/settings_provider.dart';

export 'package:wavvy/player_sheets/layouts/player_layout_data.dart';

/// The ways the Player page of the Now Playing sheet can look. Only that page
/// changes: Queue, Lyrics, About and the Visualizer are the same in all of
/// them, and so are the seek bar, the transport and the mode buttons (see
/// layout_parts.dart).
///
/// Saved by index: add new layouts at the end.
enum PlayerLayout {
  vinyl,
  itunes,
  coverFlow,
  hifi,
  poster,
  lyrics,
  twoPane,
  cassette,
  cd,
}

extension PlayerLayoutInfo on PlayerLayout {
  String get label => switch (this) {
    PlayerLayout.vinyl => 'Vinyl',
    PlayerLayout.itunes => 'iTunes LCD',
    PlayerLayout.coverFlow => 'Cover Flow',
    PlayerLayout.hifi => 'Hi-Fi deck',
    PlayerLayout.poster => 'Poster',
    PlayerLayout.lyrics => 'Lyrics first',
    PlayerLayout.twoPane => 'Two panes',
    PlayerLayout.cassette => 'Cassette deck',
    PlayerLayout.cd => 'CD player',
  };

  String get description => switch (this) {
    PlayerLayout.vinyl => 'A record and tonearm, with the controls below.',
    PlayerLayout.itunes =>
      'A big cover with a glass reflection under an LCD display, like iTunes.',
    PlayerLayout.coverFlow =>
      'Swipe through the queue as tilted covers. Tap the middle one to flip it.',
    PlayerLayout.hifi =>
      'A brushed-metal faceplate with an LCD, level meters and a knob.',
    PlayerLayout.poster =>
      'The cover fills the screen, blurred, with big type and few controls.',
    PlayerLayout.lyrics =>
      'A small cover on top and the lyrics taking most of the screen.',
    PlayerLayout.twoPane =>
      'The cover and controls on one side, the queue or lyrics on the other.',
    PlayerLayout.cassette =>
      'A tape deck with turning spools, a handwritten label and a tape counter.',
    PlayerLayout.cd =>
      'A spinning disc and a segment display, like a portable CD player.',
  };
}

/// Landscape phones and tablets: wide enough that two panes fit.
bool isWidePlayerScreen(Size size) =>
    size.width >= 840 || (size.width > size.height && size.width >= 600);

/// Whether the two-pane layout is built. Until it is, wide screens keep the
/// chosen layout (and the sheet keeps its Queue and Lyrics pages). The two-pane
/// layout turns this on when it registers itself below.
const bool kTwoPaneReady = true;

/// The layout to show: the one the user chose, unless "Two panes on wide
/// screens" is on and the screen is wide.
PlayerLayout resolvePlayerLayout(SettingsState settings, Size size) {
  if (kTwoPaneReady &&
      settings.playerLayoutAdaptive &&
      isWidePlayerScreen(size)) {
    return PlayerLayout.twoPane;
  }
  return PlayerLayout.values[settings.playerLayout.clamp(
    0,
    PlayerLayout.values.length - 1,
  )];
}

typedef PlayerLayoutBuilder = Widget Function(PlayerLayoutData data);

/// How each layout is built. Each layout adds its own entry here.
final Map<PlayerLayout, PlayerLayoutBuilder> kPlayerLayoutBuilders = {
  PlayerLayout.vinyl: (d) => VinylLayout(data: d),
  // The others show the vinyl deck until their own layout is registered.
  PlayerLayout.itunes: (d) => ItunesLayout(data: d),
  PlayerLayout.coverFlow: (d) => CoverFlowLayout(data: d),
  PlayerLayout.hifi: (d) => HifiLayout(data: d),
  PlayerLayout.poster: (d) => PosterLayout(data: d),
  PlayerLayout.lyrics: (d) => LyricsFirstLayout(data: d),
  PlayerLayout.twoPane: (d) => TwoPaneLayout(data: d),
  // Show the vinyl deck until their own layout is registered.
  PlayerLayout.cassette: (d) => VinylLayout(data: d),
  PlayerLayout.cd: (d) => VinylLayout(data: d),
};

/// A thumbnail of each layout for the picker in Settings, drawn from painted
/// shapes (no song needed). Each layout adds its own entry here; the picker
/// shows an icon for any that is missing.
final Map<PlayerLayout, WidgetBuilder> kPlayerLayoutPreviews = {
  PlayerLayout.vinyl: (_) => const VinylLayoutPreview(),
  PlayerLayout.itunes: (_) => const ItunesLayoutPreview(),
  PlayerLayout.coverFlow: (_) => const CoverFlowLayoutPreview(),
  PlayerLayout.hifi: (_) => const HifiLayoutPreview(),
  PlayerLayout.poster: (_) => const PosterLayoutPreview(),
  PlayerLayout.lyrics: (_) => const LyricsFirstLayoutPreview(),
  PlayerLayout.twoPane: (_) => const TwoPaneLayoutPreview(),
};

/// Shows the chosen layout for the playing song.
class PlayerLayoutHost extends ConsumerWidget {
  const PlayerLayoutHost({super.key, required this.data});
  final PlayerLayoutData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(settingsProvider.select((s) => s.playerLayout));
    final adaptive = ref.watch(
      settingsProvider.select((s) => s.playerLayoutAdaptive),
    );
    final layout = resolvePlayerLayout(
      SettingsState(playerLayout: chosen, playerLayoutAdaptive: adaptive),
      MediaQuery.sizeOf(context),
    );
    // A new key per layout, so state from one never leaks into another.
    return KeyedSubtree(
      key: ValueKey(layout),
      child: kPlayerLayoutBuilders[layout]!(data),
    );
  }
}
