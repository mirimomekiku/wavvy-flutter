import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wavvy/models/lyric.dart';
import 'package:wavvy/providers/lyrics_provider.dart';
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
  final int _maxLines = 1; // Increased limit slightly for better cards
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

        await Share.shareXFiles([
          XFile(file.path),
        ], text: 'Listening to ${widget.song.title} on Wavvy 🎵');
      }
    } catch (e) {
      AppSnackbar.showErrorSnackBar("Error sharing", "$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedIndices = _selectedIndices.toList()..sort();
    final selectedLyrics = sortedIndices.map((i) => widget.lyrics[i]).toList();
    final a = Aqua.of(context);

    return Scaffold(
      backgroundColor: a.background,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: a.toolbar,
            ),
            border: Border(bottom: BorderSide(color: a.toolbarBorder)),
          ),
        ),
        leading: GelButton(
          circular: true,
          size: 32,
          tooltip: "Back",
          onPressed: () => Navigator.maybePop(context),
          child: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: GelButton(
              primary: true,
              size: 32,
              width: 92,
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
                color: a.background,
                border: Border(top: BorderSide(color: a.border)),
              ),
              child: Column(
                children: [
                  AquaSectionBar(
                    title: "Select Lyrics",
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        "${_selectedIndices.length}/$_maxLines lines",
                        style: TextStyle(
                          color: a.textSecondary,
                          fontSize: 12,
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
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? null
                                  : (index.isEven ? a.background : a.stripe),
                              gradient: isSelected
                                  ? LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: a.selection,
                                    )
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    line.text,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : a.text,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
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
    return AspectRatio(
      aspectRatio: 4 / 5, // Standard Social Media Portrait
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Ds.radiusL),
          color: Colors.grey[900],
          image: _artworkBytes != null
              ? DecorationImage(
                  image: MemoryImage(_artworkBytes!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Ds.radiusL),
          child: Stack(
            fit: StackFit.expand,
            children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                child: Container(color: Colors.black.withValues(alpha: 0.3)),
              ),

              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),

              // 3. Content
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),

                    // Artwork Thumb (Clean Shadow)
                    if (_artworkBytes != null)
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Ds.radiusS),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black45,
                              blurRadius: 5,
                              offset: Offset(0, 2),
                            ),
                          ],
                          image: DecorationImage(
                            image: MemoryImage(_artworkBytes!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),

                    const Spacer(),

                    // Lyrics
                    if (lines.isEmpty)
                      Text(
                        "Tap lyrics below to preview",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                        ),
                      )
                    else
                      ...lines.map(
                        (l) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            l.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              letterSpacing: -0.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black87,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    const Spacer(),

                    // Footer / Brand Tag
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(Ds.radiusM),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.music_note_rounded,
                            color: widget.themeColor,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              "${widget.song.title} • ${widget.song.artist}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Wavvy",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
