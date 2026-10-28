import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavvy/providers/album_art_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/palette_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_texture.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';
import 'package:wavvy/widgets/now_playing_card.dart';

// ------------------------------------------------------------ Remembered look

const _kStyle = 'share_card_style';
const _kAspect = 'share_card_aspect';

/// The style and shape last used, kept in SharedPreferences.
@immutable
class NowPlayingCardPrefs {
  const NowPlayingCardPrefs({
    this.style = NowPlayingCardStyle.aqua,
    this.aspect = NowPlayingCardAspect.square,
  });
  final NowPlayingCardStyle style;
  final NowPlayingCardAspect aspect;
}

final nowPlayingCardPrefsProvider =
    NotifierProvider<NowPlayingCardPrefsNotifier, NowPlayingCardPrefs>(
      NowPlayingCardPrefsNotifier.new,
    );

class NowPlayingCardPrefsNotifier extends Notifier<NowPlayingCardPrefs> {
  bool _disposed = false;
  // A choice made before the saved one has loaded wins over it.
  bool _chosen = false;

  @override
  NowPlayingCardPrefs build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    Future.microtask(_load);
    return const NowPlayingCardPrefs();
  }

  Future<void> _load() async {
    try {
      final prefs = SharedPreferencesAsync();
      final style = await prefs.getString(_kStyle);
      final aspect = await prefs.getString(_kAspect);
      if (_disposed || _chosen) return;
      state = NowPlayingCardPrefs(
        style: NowPlayingCardStyle.values.asNameMap()[style] ?? state.style,
        aspect: NowPlayingCardAspect.values.asNameMap()[aspect] ?? state.aspect,
      );
    } catch (e) {
      // The card works with its defaults.
      debugPrint('could not load share card settings: $e');
    }
  }

  Future<void> setStyle(NowPlayingCardStyle style) async {
    _chosen = true;
    state = NowPlayingCardPrefs(style: style, aspect: state.aspect);
    await _save(_kStyle, style.name);
  }

  Future<void> setAspect(NowPlayingCardAspect aspect) async {
    _chosen = true;
    state = NowPlayingCardPrefs(style: state.style, aspect: aspect);
    await _save(_kAspect, aspect.name);
  }

  Future<void> _save(String key, String value) async {
    try {
      await SharedPreferencesAsync().setString(key, value);
    } catch (e) {
      debugPrint('could not save share card settings: $e');
    }
  }
}

// ------------------------------------------------------------------- Export

/// Renders [card] off-screen to a PNG. [cover] is decoded first so the image
/// is in the capture. Overridden in tests.
typedef NowPlayingCardCapturer =
    Future<Uint8List> Function(
      BuildContext context,
      Widget card,
      NowPlayingCardSizing sizing,
      Uint8List? cover,
    );

/// Writes [png] to a file and shares it with [text]. Overridden in tests.
typedef NowPlayingCardSharer =
    Future<void> Function(Uint8List png, String text);

Future<Uint8List> captureNowPlayingCard(
  BuildContext context,
  Widget card,
  NowPlayingCardSizing sizing,
  Uint8List? cover,
) async {
  if (cover != null) {
    // The same bytes object the card's Image.memory uses, so it is a cache hit.
    await precacheImage(MemoryImage(cover), context, onError: (_, _) {});
  }
  if (!context.mounted) throw StateError('The screen was closed');
  return ScreenshotController().captureFromWidget(
    card,
    context: context,
    targetSize: sizing.logical,
    pixelRatio: sizing.pixelRatio,
    delay: const Duration(milliseconds: 150),
  );
}

/// One fixed file name, overwritten each time like the lyric card's: the
/// receiving app reads it after this returns, so it is not deleted here.
Future<void> shareNowPlayingCard(Uint8List png, String text) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/wavvy_now_playing_card.png');
  await file.writeAsBytes(png, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: text,
    ),
  );
}

final nowPlayingCardCapturerProvider = Provider<NowPlayingCardCapturer>(
  (ref) => captureNowPlayingCard,
);
final nowPlayingCardSharerProvider = Provider<NowPlayingCardSharer>(
  (ref) => shareNowPlayingCard,
);

/// The song's cover at export size: the embedded picture, else a fetched one.
/// A file opened from outside the library (negative id) has no MediaStore art,
/// so it gets a plain card.
final nowPlayingCoverProvider = FutureProvider.autoDispose
    .family<Uint8List?, int>((ref, songId) async {
      if (songId < 0) return null;
      try {
        final bytes = await ref
            .read(audioQueryProvider)
            .queryArtwork(
              songId,
              ArtworkType.AUDIO,
              format: ArtworkFormat.JPEG,
              size: 1000,
              quality: 100,
            );
        if (bytes != null && bytes.isNotEmpty) return bytes;
        return await cachedArtThumbForSong(ref, songId, px: 1000);
      } catch (e) {
        debugPrint('could not load the cover for the share card: $e');
        return null;
      }
    });

// ------------------------------------------------------------------- Screen

/// Previews the "Now playing" card of [song] and shares it as an image.
class NowPlayingCardScreen extends ConsumerStatefulWidget {
  const NowPlayingCardScreen({super.key, required this.song});
  final SongModel song;

  @override
  ConsumerState<NowPlayingCardScreen> createState() =>
      _NowPlayingCardScreenState();
}

class _NowPlayingCardScreenState extends ConsumerState<NowPlayingCardScreen> {
  bool _showMark = true;
  bool _showTime = true;
  bool _busy = false;

  /// The card for what is on screen now; [watch] rebuilds on a change.
  NowPlayingCardData _data({required bool watch}) {
    final song = widget.song;
    T read<T>(ProviderListenable<T> p) => watch ? ref.watch(p) : ref.read(p);
    final playing =
        read(playerProvider.select((s) => s.currentSong?.id)) == song.id;
    final cover = read(nowPlayingCoverProvider(song.id)).asData?.value;
    final palette = playing ? read(paletteProvider) : null;
    var total = playing ? read(durationProvider) : Duration.zero;
    if (total == Duration.zero) {
      total = Duration(milliseconds: song.duration ?? 0);
    }
    final artist = song.artist;
    final album = song.album;
    return NowPlayingCardData(
      title: song.title,
      artist: artist == null || artist.isEmpty || artist == '<unknown>'
          ? 'Unknown Artist'
          : artist,
      album: album == null || album == '<unknown>' ? null : album,
      cover: cover,
      seed: song.id,
      accent: palette?.playerColor ?? Wv.of(context).accent,
      position: playing && _showTime ? read(positionProvider) : null,
      duration: playing && _showTime ? total : null,
    );
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = _data(watch: false);
      final prefs = ref.read(nowPlayingCardPrefsProvider);
      final card = NowPlayingCard(
        data: data,
        style: prefs.style,
        aspect: prefs.aspect,
        showMark: _showMark,
      );
      final png = await ref.read(nowPlayingCardCapturerProvider)(
        context,
        card,
        nowPlayingCardSizing(prefs.aspect),
        data.cover,
      );
      await ref.read(nowPlayingCardSharerProvider)(
        png,
        '${data.title} - ${data.artist}',
      );
    } catch (e) {
      AppSnackbar.showErrorSnackBar('Error sharing', '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final prefs = ref.watch(nowPlayingCardPrefsProvider);
    final notifier = ref.read(nowPlayingCardPrefsProvider.notifier);
    final playing =
        ref.watch(playerProvider.select((s) => s.currentSong?.id)) ==
        widget.song.id;
    final data = _data(watch: true);
    final sizing = nowPlayingCardSizing(prefs.aspect);

    return WvBackdrop(
      child: Scaffold(
        backgroundColor: a.pageColor,
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Share card',
            style: TextStyle(
              color: a.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          leading: WvButton(
            circular: true,
            size: 40,
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
            child: const Icon(Icons.arrow_back_rounded),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: WvButton(
                primary: true,
                size: 40,
                squircle: true,
                width: 100,
                tooltip: 'Share',
                onPressed: _busy ? null : _share,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.ios_share, size: 16),
                    SizedBox(width: 4),
                    Text('Share'),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  // The card is laid out at its export size and scaled to fit.
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox.fromSize(
                      size: sizing.logical,
                      child: NowPlayingCard(
                        data: data,
                        style: prefs.style,
                        aspect: prefs.aspect,
                        showMark: _showMark,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.42,
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: a.surface,
                  image: a.pageTexture,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(Ds.radiusXL),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    12 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(a, 'Style'),
                      WvChips(
                        labels: [
                          for (final s in NowPlayingCardStyle.values) s.label,
                        ],
                        selected: prefs.style.index,
                        onChanged: (i) =>
                            notifier.setStyle(NowPlayingCardStyle.values[i]),
                      ),
                      const SizedBox(height: 8),
                      _label(a, 'Shape'),
                      WvChips(
                        labels: [
                          for (final s in NowPlayingCardAspect.values) s.label,
                        ],
                        selected: prefs.aspect.index,
                        onChanged: (i) =>
                            notifier.setAspect(NowPlayingCardAspect.values[i]),
                      ),
                      const SizedBox(height: 4),
                      _toggle(
                        a,
                        'Wavvy mark',
                        _showMark,
                        (v) => setState(() => _showMark = v),
                      ),
                      if (playing)
                        _toggle(
                          a,
                          'Time and progress',
                          _showTime,
                          (v) => setState(() => _showTime = v),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(WvPalette a, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: a.textSecondary,
      ),
    ),
  );

  Widget _toggle(
    WvPalette a,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: a.text,
            ),
          ),
        ),
        AquaSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}
