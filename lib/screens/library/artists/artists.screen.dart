import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/context_ext.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/library_provider.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:wavvy/screens/library/artists/view/artist.screen.dart';
import 'package:wavvy/widgets/aqua_song_list.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/widgets/floating_app_bar.dart';

class AllArtistsScreen extends ConsumerWidget {
  const AllArtistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(libraryProvider.select((s) => s.artists));
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
                title: "Artists",
                showSearch: false,
                leading: aquaBackButton(),
              ),
              Expanded(
                child: Builder(builder: (context) {
                  if (items.isEmpty) {
                    return const AquaEmptyMessage(
                      message: "No Artists Found",
                      icon: Icons.person_rounded,
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
                      final artist = items[index];
                      return AquaGridTile(
                        circular: true,
                        onTap: () =>
                            AppNav.push(ArtistDetailScreen(artist: artist)),
                        title: artist.artist,
                        subtitle:
                            "${artist.numberOfTracks} Songs • ${artist.numberOfAlbums} Albums",
                        artworkBuilder: (size) => aquaArtwork(
                          context,
                          id: artist.id,
                          type: ArtworkType.ARTIST,
                          size: size,
                          placeholder: Icons.person_rounded,
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
