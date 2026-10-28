import 'package:flutter/widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// What a Now Playing layout is given: the playing song and the places it can
/// send the user. A null callback means that page is turned off in Settings.
class PlayerLayoutData {
  const PlayerLayoutData({
    required this.song,
    this.onLyrics,
    this.onArtist,
    this.onQueue,
  });

  final SongModel song;

  /// Opens the Lyrics page.
  final VoidCallback? onLyrics;

  /// Opens the About (artist) page.
  final VoidCallback? onArtist;

  /// Opens the Queue page.
  final VoidCallback? onQueue;
}
