import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

/// A song outside the library (opened from a file manager or shared to
/// Wavvy) has a negative id, so it never collides with a MediaStore id. Such a
/// song is a temporary queue item: no delete, tag editing, favorites or
/// playlists.
extension ExternalSong on SongModel {
  bool get isExternal => id < 0;
}

/// An audio file Android asked Wavvy to open, as the native side describes it.
class ExternalAudio {
  const ExternalAudio({
    required this.uri,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.displayName,
    this.mediaId,
  });

  /// content:// or file:// URI the player reads.
  final String uri;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;

  /// The file name from the provider, when it has one.
  final String? displayName;

  /// The MediaStore audio id, when the URI is a MediaStore audio URI.
  final int? mediaId;

  /// Null when [map] has no usable URI.
  static ExternalAudio? fromMap(Object? map) {
    if (map is! Map) return null;
    final uri = map['uri'];
    if (uri is! String || uri.trim().isEmpty) return null;
    String? text(String key) {
      final v = map[key];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    int? number(String key) {
      final v = map[key];
      return v is num ? v.toInt() : null;
    }

    return ExternalAudio(
      uri: uri.trim(),
      title: text('title'),
      artist: text('artist'),
      album: text('album'),
      durationMs: number('duration'),
      displayName: text('displayName'),
      mediaId: number('mediaId'),
    );
  }
}

/// The native side of "Open with". Overridden in tests.
abstract class ExternalAudioChannel {
  /// The file the app was started with, once. Null when there is none.
  Future<ExternalAudio?> takePending();

  /// Called for a file opened while the app is running.
  set onOpen(void Function(ExternalAudio audio)? handler);
}

class MethodExternalAudioChannel implements ExternalAudioChannel {
  static const _channel = MethodChannel(
    'com.mirimomekiku.wavvy/external_audio',
  );

  @override
  Future<ExternalAudio?> takePending() async {
    try {
      return ExternalAudio.fromMap(
        await _channel.invokeMethod<Object?>('takePending'),
      );
    } catch (e) {
      debugPrint('external audio unavailable: $e');
      return null;
    }
  }

  @override
  set onOpen(void Function(ExternalAudio audio)? handler) {
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'open') return;
      final audio = ExternalAudio.fromMap(call.arguments);
      if (audio != null) handler(audio);
    });
  }
}

final externalAudioChannelProvider = Provider<ExternalAudioChannel>(
  (ref) => MethodExternalAudioChannel(),
);

/// Plays what [ExternalAudioChannel] hands over: the library song when the
/// file is one, otherwise a temporary song that plays alone.
class ExternalAudioHandler {
  ExternalAudioHandler(
    this._ref, {
    this.libraryTimeout = const Duration(seconds: 8),
  });

  final Ref _ref;

  /// How long to wait for the library when the file should be in it.
  final Duration libraryTimeout;

  Future<void> open(ExternalAudio audio) async {
    try {
      final song = await _libraryMatch(audio) ?? songFor(audio);
      final library = _ref.read(libraryProvider);
      final context = song.isExternal
          ? [song]
          : (library.filteredSongs.any((s) => s.id == song.id)
                ? library.filteredSongs
                : library.songs);
      await _ref
          .read(playerProvider.notifier)
          .playSong(song, contextList: context);
    } catch (e) {
      debugPrint('could not open ${audio.uri}: $e');
      AppSnackbar.showErrorSnackBar(
        'Cannot play file',
        'Wavvy could not open that audio file.',
      );
    }
  }

  /// The library song for a MediaStore file, waiting for the library to load.
  Future<SongModel?> _libraryMatch(ExternalAudio audio) async {
    final id = audio.mediaId;
    if (id == null) return null;
    SongModel? find() =>
        _ref.read(libraryProvider).songs.where((s) => s.id == id).firstOrNull;

    final end = DateTime.now().add(libraryTimeout);
    while (true) {
      final found = find();
      if (found != null) return found;
      final library = _ref.read(libraryProvider);
      // Loaded (or refused) and still not there: it is not in the library.
      if (library.permissionDenied ||
          (!library.isLoading && library.songs.isNotEmpty)) {
        return null;
      }
      if (DateTime.now().isAfter(end)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// A temporary song for a file that is not in the library.
  @visibleForTesting
  static SongModel songFor(ExternalAudio audio) {
    final name = _fileName(audio);
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 && dot < name.length - 1 ? name.substring(dot + 1) : '';
    final parsed = Uri.tryParse(audio.uri);
    final path = parsed != null && parsed.scheme == 'file'
        ? Uri.decodeComponent(parsed.path)
        : '';
    final duration = audio.durationMs;
    return SongModel({
      '_id': externalId(audio.uri),
      '_data': path,
      '_uri': audio.uri,
      '_display_name': name,
      '_display_name_wo_ext': base,
      '_size': 0,
      'file_extension': ext,
      'title': audio.title ?? base,
      'artist': audio.artist,
      'album': audio.album,
      'duration': duration != null && duration > 0 ? duration : null,
      'is_music': true,
    });
  }

  /// The file name: the provider's, else the last part of the URI.
  static String _fileName(ExternalAudio audio) {
    final shown = audio.displayName;
    if (shown != null) return shown;
    final segments = Uri.tryParse(audio.uri)?.pathSegments ?? const <String>[];
    final last = segments.isEmpty ? '' : segments.last.trim();
    return last.isEmpty ? 'Unknown' : last;
  }

  /// A stable negative id for [uri] (FNV-1a), never a MediaStore id.
  @visibleForTesting
  static int externalId(String uri) {
    var hash = 0x811c9dc5;
    for (final unit in uri.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return -(1 + (hash & 0x7fffffff));
  }
}

final externalAudioHandlerProvider = Provider<ExternalAudioHandler>(
  (ref) => ExternalAudioHandler(ref),
);

/// Plays the file Wavvy was started with and each one opened later. Watch it
/// once from the app root.
final externalAudioProvider = Provider<void>((ref) {
  final channel = ref.read(externalAudioChannelProvider);
  final handler = ref.read(externalAudioHandlerProvider);
  channel.onOpen = (audio) => unawaited(handler.open(audio));
  ref.onDispose(() => channel.onOpen = null);
  unawaited(
    channel
        .takePending()
        .then((audio) {
          if (audio != null) return handler.open(audio);
        })
        .catchError((Object e) => debugPrint('pending audio failed: $e')),
  );
});
