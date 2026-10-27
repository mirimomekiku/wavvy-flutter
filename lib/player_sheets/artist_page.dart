import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/artist_info_provider.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/providers/player_provider.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/pixel_art.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/utils/player.utils.dart';
import 'package:wavvy/widgets/wv_song_list.dart';

/// The player's Artist tab as three Aqua windows: the artist (photo, name and
/// an LCD readout of what you own), the biography, and their songs on this
/// device.
class ArtistInfoPage extends ConsumerWidget {
  const ArtistInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Wv.of(context);
    final info = ref.watch(artistInfoProvider);
    final player = ref.watch(playerProvider);
    final song = player.currentSong;
    final library = ref.watch(libraryProvider);

    final name = song?.artist ?? 'Unknown Artist';
    final known =
        song != null && song.artist != null && song.artist != '<unknown>';
    final mine = library.songs.where((s) => s.artist == song?.artist).toList();
    final albums = {for (final s in mine) s.album}.length;
    final totalMs = mine.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final artistModel = library.artists
        .where((x) => x.id == song?.artistId)
        .firstOrNull;

    final failed = info.bio.startsWith('Could not load');
    final seed = song?.artistId ?? song?.id ?? 0;
    Widget placeholder() => WvMediaPlaceholder(seed: seed, size: 92);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        0,
        16,
        0,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ---- Who
              AquaWindow(
                title: 'Artist',
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        WvArtwork(
                          radius: 10,
                          elevated: true,
                          child: SizedBox.square(
                            dimension: 92,
                            child: info.imageUrl.isNotEmpty
                                ? Image.network(
                                    info.imageUrl,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (c, child, progress) =>
                                        progress == null
                                        ? child
                                        : placeholder(),
                                    errorBuilder: (c, o, s) => placeholder(),
                                  )
                                : placeholder(),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: a.text,
                                  fontSize: 21,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                song?.album ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: a.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (mine.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: AquaLcdCell(
                              value: '${mine.length}',
                              label: mine.length == 1 ? 'Track' : 'Tracks',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AquaLcdCell(
                              value: '$albums',
                              label: albums == 1 ? 'Album' : 'Albums',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AquaLcdCell(
                              value: PlayerUtils.formatTotalTime(totalMs),
                              label: 'Playing time',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // ---- About
              AquaWindow(
                title: 'About',
                subtitle: known ? 'Biography from Genius' : null,
                action: failed ? 'Retry' : null,
                onAction: failed
                    ? () => ref
                          .read(artistInfoProvider.notifier)
                          .refreshForSong(song)
                    : null,
                padding: const EdgeInsets.all(14),
                child: !known
                    ? _Note(
                        icon: Icons.person_off_outlined,
                        text: 'There is no artist information for this song.',
                      )
                    : info.isLoading
                    ? const Row(
                        children: [
                          AquaSpinner(size: 24),
                          SizedBox(width: 12),
                          Expanded(child: Text('Loading artist information…')),
                        ],
                      )
                    : info.bio.isEmpty
                    ? const _Note(
                        icon: Icons.info_outline_rounded,
                        text: 'No information found.',
                      )
                    : failed ||
                          info.bio.startsWith(
                            'Artist information is unavailable',
                          )
                    ? _Note(icon: Icons.cloud_off_rounded, text: info.bio)
                    : _Bio(key: ValueKey(info.bio), text: info.bio),
              ),

              // ---- Their songs here
              if (mine.isNotEmpty)
                AquaWindow(
                  title: 'In your library',
                  subtitle:
                      '${mine.length} ${mine.length == 1 ? 'track' : 'tracks'}',
                  action: artistModel == null ? null : 'Open',
                  onAction: artistModel == null
                      ? null
                      : () => AppNav.push(
                          ArtistDetailScreen(artist: artistModel),
                        ),
                  child: Column(
                    children: [
                      for (var i = 0; i < mine.length.clamp(0, 5); i++)
                        WvSongRow(
                          song: mine[i],
                          index: i,
                          isCurrent: song?.id == mine[i].id,
                          isPlaying: player.isPlaying,
                          secondary: mine[i].album ?? 'Unknown Album',
                          onTap: () => ref
                              .read(playerProvider.notifier)
                              .playSong(mine[i], contextList: mine),
                          onAction: () => ref
                              .read(playerProvider.notifier)
                              .addToQueue(mine[i]),
                          actionIcon: Icons.playlist_add_rounded,
                          actionTooltip: 'Add to queue',
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

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: a.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: a.textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// A biography that starts collapsed when it is long.
class _Bio extends StatefulWidget {
  const _Bio({super.key, required this.text});
  final String text;

  @override
  State<_Bio> createState() => _BioState();
}

class _BioState extends State<_Bio> {
  static const _collapsedLength = 420;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    final long = widget.text.length > _collapsedLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: Ds.medium,
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            maxLines: long && !_open ? 7 : null,
            overflow: long && !_open ? TextOverflow.fade : TextOverflow.clip,
            style: TextStyle(color: a.text, fontSize: 14, height: 1.55),
          ),
        ),
        if (long)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _open = !_open),
              child: Text(_open ? 'Show less' : 'Show more'),
            ),
          ),
      ],
    );
  }
}
