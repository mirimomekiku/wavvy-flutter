import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/playlists_provider.dart';
import 'package:wavvy/screens/library/playlists/view/playlist.screen.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/aqua_song_list.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/floating_app_bar.dart';
import 'package:wavvy/widgets/playlist_dialogs.dart';

class AllLocalPlaylistsScreen extends ConsumerWidget {
  const AllLocalPlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider.select((s) => s.playlists));
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      bottomNavigationBar: BottomMiniPlayer(showTabView: false),
      body: Column(
        children: [
          FloatingAppBar(
            title: "My Playlists",
            showSearch: false,
            leading: aquaBackButton(),
            actions: [
              GelButton(
                circular: true,
                tooltip: "New Playlist",
                onPressed: () => showNewPlaylistDialog(ref),
                child: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          Expanded(
            child: Builder(builder: (context) {
              if (playlists.isEmpty) {
                return const AquaEmptyMessage(
                  message: "No custom playlists yet.",
                  icon: Icons.queue_music_rounded,
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
                ),
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return _buildPlaylistCard(context, ref, playlist);
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistCard(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> playlist,
  ) {
    final a = Aqua.of(context);
    return AquaGridTile(
      onTap: () async {
        AppNav.push(
          PlaylistDetailScreen(
            playlistId: playlist['id'],
            playlistName: playlist['name'],
          ),
        );
      },
      onLongPress: () =>
          showDeletePlaylistDialog(ref, playlist['id'], playlist['name']),
      title: playlist['name'],
      artworkBuilder: (size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: Aqua.gel(a.gelBlue),
        ),
        child: Icon(
          Icons.queue_music_rounded,
          size: size * 0.45,
          color: Colors.white,
        ),
      ),
    );
  }
}
