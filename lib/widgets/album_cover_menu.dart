import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/providers/album_art_provider.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/utils/snackbar.utils.dart';

/// Looks for the cover of one album now, whatever the Settings toggle says
/// (it is an explicit tap), and tells the user how it went.
Future<void> findCoverForAlbum(WidgetRef ref, AlbumModel album) async {
  final r = albumRefForAlbum(album);
  final result = await ref.read(albumArtFinderProvider).fetch(r, force: true);
  switch (result) {
    case ArtFetch.found:
      AppSnackbar.showSuccess('Cover found', album.album);
    case ArtFetch.notFound:
      AppSnackbar.showSnackbar(
        'No cover found',
        'MusicBrainz has no cover for ${album.album}.',
      );
    case ArtFetch.offline:
      AppSnackbar.showErrorSnackBar(
        'Could not reach the cover service',
        'Check your connection and try again.',
      );
    case ArtFetch.rateLimited:
      AppSnackbar.showErrorSnackBar(
        'The cover service is busy',
        'Try again in a little while.',
      );
    case ArtFetch.error:
      AppSnackbar.showErrorSnackBar(
        'Could not get a cover',
        'Something went wrong. Try again later.',
      );
    case ArtFetch.skipped:
      AppSnackbar.showSnackbar(
        'Nothing to look up',
        'This album needs an album name and a single artist.',
      );
  }
}

/// The album screen's cover menu: Find cover, and Remove fetched cover when
/// one was fetched. A small button for the header's top right.
class AlbumCoverMenuButton extends ConsumerWidget {
  const AlbumCoverMenuButton({super.key, required this.album});
  final AlbumModel album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = albumRefForAlbum(album).key;
    return IconButton(
      tooltip: 'Cover',
      icon: const Icon(Icons.image_search_rounded),
      onPressed: () => showAquaSheet<void>(
        context: context,
        title: 'Cover',
        builder: (sheetContext) {
          final fetched = ref.read(albumArtFileProvider(key)) != null;
          return ListView(
            shrinkWrap: true,
            padding: EdgeInsets.only(
              top: 12,
              bottom: 12 + MediaQuery.paddingOf(sheetContext).bottom,
            ),
            children: [
              AquaMenuGroup(
                rows: [
                  AquaMenuRow(
                    icon: Icons.image_search_rounded,
                    label: 'Find cover',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      findCoverForAlbum(ref, album);
                    },
                  ),
                  if (fetched)
                    AquaMenuRow(
                      icon: Icons.hide_image_outlined,
                      label: 'Remove fetched cover',
                      destructive: true,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        ref.read(albumArtIndexProvider.notifier).remove(key);
                      },
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
