import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

class LyricCardGenerator extends ConsumerStatefulWidget {
  final SongModel song;
  final List<Lyric> lyrics;
  final Color themeColor;

  const LyricCardGenerator({
    super.key,
    required this.song,
    required this.lyrics,
    required this.themeColor,
  });

  @override
  ConsumerState<LyricCardGenerator> createState() => _LyricCardGeneratorState();
}

class _LyricCardGeneratorState extends ConsumerState<LyricCardGenerator> {
  final ScreenshotController _screenshotController = ScreenshotController();
  final Set<int> _selectedIndices = {}; // Track selected lines
  final int _maxLines = 4; // Increased limit slightly for better cards
  Uint8List? _artworkBytes;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
    // Auto-select current line
    try {
      final currentIdx = ref.read(lyricsProvider).currentIndex;
      if (currentIdx != -1 && currentIdx < widget.lyrics.length) {
        _selectedIndices.add(currentIdx);
      }
    } catch (_) {}
  }

  Future<void> _loadArtwork() async {
    final OnAudioQuery audioQuery = OnAudioQuery();
    try {
      final bytes = await audioQuery.queryArtwork(
        widget.song.id,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 1000,
        quality: 100,
      );
      if (mounted) {
        setState(() {
          _artworkBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint("Could not load artwork for share card: $e");
    }
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        if (_selectedIndices.length < _maxLines) {
          _selectedIndices.add(index);
        } else {}
      }
    });
  }

  Future<void> _shareCard() async {
    try {
      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/wavvy_lyric_card.png';

      final imageBytes = await _screenshotController.capture(pixelRatio: 3.0);

      if (imageBytes != null) {
        final file = File(imagePath);
        await file.writeAsBytes(imageBytes);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'Listening to ${widget.song.title} on Wavvy',
          ),
        );
      }
    } catch (e) {
      AppSnackbar.showErrorSnackBar("Error sharing", "$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedIndices = _selectedIndices.toList()..sort();
    final selectedLyrics = sortedIndices.map((i) => widget.lyrics[i]).toList();
    final a = Wv.of(context);

    return Scaffold(
      backgroundColor: a.background,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: a.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const WvKicker('SHARE CARD'),
            Text(
              "Share lyrics",
              style: TextStyle(
                color: a.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        leading: WvButton(
          circular: true,
          size: 40,
          tooltip: "Back",
          onPressed: () => Navigator.maybePop(context),
          child: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: WvButton(
              primary: true,
              size: 40,
              squircle: true,
              width: 100,
              tooltip: "Share",
              onPressed: sortedIndices.isEmpty ? null : _shareCard,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ios_share, size: 16),
                  SizedBox(width: 4),
                  Text("Share"),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // --- PREVIEW AREA ---
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32.0,
                    vertical: 16,
                  ),
                  child: Screenshot(
                    controller: _screenshotController,
                    child: _buildCard(selectedLyrics),
                  ),
                ),
              ),
            ),
          ),

          // --- SELECTION AREA ---
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(
                color: a.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Ds.radiusXL),
                ),
              ),
              child: Column(
                children: [
                  WvSectionHeader(
                    title: "Select Lyrics",
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        "${_selectedIndices.length}/$_maxLines lines",
                        style: TextStyle(
                          color: a.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: widget.lyrics.length,
                      itemBuilder: (context, index) {
                        final line = widget.lyrics[index];
                        final isSelected = _selectedIndices.contains(index);

                        return GestureDetector(
                          onTap: () => _toggleSelection(index),
                          child: AnimatedContainer(
                            duration: Ds.fast,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? a.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                isSelected ? 22 : 16,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    line.text,
                                    style: TextStyle(
                                      color: isSelected
                                          ? a.onPrimaryContainer
                                          : a.text,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: a.onPrimaryContainer,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- THE ACTUAL CARD DESIGN ---
  Widget _buildCard(List<Lyric> lines) {
    final a = Wv.of(context);
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: Container(
        decoration: a.frame(color: a.surface, radius: 20),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                WvKicker('Lyrics', color: a.text),
                WvSymbol(sprite: PixelSprites.note, size: 16, color: a.accent),
              ],
            ),
            const SizedBox(height: 16),
            WvArtwork(
              radius: 12,
              child: _artworkBytes == null
                  ? WvMediaPlaceholder(seed: widget.song.id, size: 72)
                  : Image.memory(
                      _artworkBytes!,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 240,
                    child: Text(
                      lines.isEmpty
                          ? 'Tap lyrics below to preview'
                          : lines.map((line) => line.text).join('\n'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'WorkSans',
                        fontSize: lines.isEmpty ? 18 : 27,
                        height: 1.35,
                        color: a.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Divider(color: a.outline.withValues(alpha: 0.4)),
            Text(
              widget.song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: a.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              widget.song.artist ?? 'Unknown Artist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: a.text, fontSize: 12),
            ),
            const SizedBox(height: 10),
            WvKicker('Wavvy', color: a.text),
          ],
        ),
      ),
    );
  }
}
