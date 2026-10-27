import 'package:flutter/material.dart' hide AppBar;
import 'package:flutter/services.dart';
import 'package:flutter_appbar/flutter_appbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/core/navigation.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/screens/downloader/downloader.screen.dart';
import 'package:wavvy/screens/home/view/library_view.dart';
import 'package:wavvy/screens/home/widgets/songs_header_app_bar.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/bottom_bar.dart';
import 'package:wavvy/screens/home/view/songs_view.dart';
import 'package:wavvy/widgets/floating_app_bar.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enableDownloader = ref.watch(
      settingsProvider.select((s) => s.enableDownloader),
    );
    final showStats = ref.watch(settingsProvider.select((s) => s.showStats));

    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
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
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: DefaultTabController(
        length: enableDownloader ? 3 : 2,
        child: Scaffold(
          backgroundColor: backgroundColor,
          bottomNavigationBar: BottomMiniPlayer(),
          body: SafeArea(
            child: TabBarView(
              children: [
                AppBarConnection(
                  appBars: [
                    if (showStats)
                      AppBar(
                        behavior: const MaterialAppBarBehavior(
                          dragOnlyExpanding: true,
                        ),
                        body: SongsHeaderAppBar(),
                      ),
                    AppBar(
                      behavior: const MaterialAppBarBehavior(floating: true),
                      body: FloatingAppBar(
                        showSearch: true,
                        title: "Wavvy",
                        actions: [
                          GelButton(
                            tooltip: "Settings",
                            circular: true,
                            onPressed: () => AppNav.pushNamed("/settings"),
                            child: const Icon(Icons.settings_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: SongsView(),
                ),
                AppBarConnection(
                  appBars: [
                    AppBar(
                      behavior: const MaterialAppBarBehavior(floating: true),
                      body: FloatingAppBar(showSearch: true, title: "Library"),
                    ),
                  ],
                  child: LibraryView(),
                ),
                if (enableDownloader)
                  AppBarConnection(
                    appBars: [
                      AppBar(
                        behavior: const MaterialAppBarBehavior(floating: true),
                        body: FloatingAppBar(
                          showSearch: true,
                          title: "Downloads",
                        ),
                      ),
                    ],
                    child: DownloaderHubScreen(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
