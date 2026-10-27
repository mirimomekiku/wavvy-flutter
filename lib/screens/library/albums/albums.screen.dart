import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/context_ext.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/widgets/aqua_song_list.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/floating_app_bar.dart';
import 'package:wavvy/screens/library/albums/view/album.screen.dart';

class AllAlbumsScreen extends ConsumerWidget {
  const AllAlbumsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(libraryProvider.select((s) => s.albums));
    return Builder(builder: (context) {
      final navBarColor = Aqua.of(context).toolbar[1];

      final Brightness iconBrightness =
          ThemeData.estimateBrightnessForColor(navBarColor) == Brightness.dark
          ? Brightness.light
          : Brightness.dark;

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: navBarColor,
          systemNavigationBarIconBrightness: iconBrightness,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: context.isDarkMode
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          bottomNavigationBar: BottomMiniPlayer(showTabView: false),
          body: Column(
            children: [
              FloatingAppBar(
                title: "Albums",
                showSearch: false,
                leading: aquaBackButton(),
              ),
              Expanded(
                child: Builder(builder: (context) {
                  if (items.isEmpty) {
                    return const AquaEmptyMessage(
                      message: "No Albums Found",
                      icon: Icons.album_rounded,
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.8,
                        ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final album = items[index];
                      return AquaGridTile(
                        onTap: () =>
                            AppNav.push(AlbumDetailScreen(album: album)),
                        title: album.album,
                        subtitle:
                            "${album.numOfSongs} Songs • ${album.artist ?? 'Unknown'}",
                        artworkBuilder: (size) => aquaArtwork(
                          context,
                          id: album.id,
                          type: ArtworkType.ALBUM,
                          size: size,
                          placeholder: Icons.album_rounded,
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      );
    });
  }
}
