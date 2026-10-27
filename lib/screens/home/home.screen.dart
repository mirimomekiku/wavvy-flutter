import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/screens/home/view/home_view.dart';
import 'package:wavvy/screens/library/library_tab.dart';
import 'package:wavvy/screens/search/search_tab.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';
import 'package:wavvy/widgets/bottom_bar.dart';

/// The app shell: Home / Library / Search tabs over the mini-player and nav.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final a = Wv.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        // Matches the Expressive navigation bar surface.
        systemNavigationBarColor: a.surface,
        systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: theme.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          extendBody: true,
          backgroundColor: a.background,
          bottomNavigationBar: const BottomMiniPlayer(),
          // No SafeArea: each tab's heading pads itself below the status bar so
          // its background paints behind it.
          body: const TabBarView(
            // Pages scroll horizontally inside (shelves, chips), so switching
            // tabs is done from the bottom nav only.
            physics: NeverScrollableScrollPhysics(),
            children: [
              _KeepAlive(child: HomeView()),
              _KeepAlive(child: LibraryTab()),
              _KeepAlive(child: SearchTab()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps a tab's state (scroll position, typed search text) alive while
/// another tab is showing.
class _KeepAlive extends StatefulWidget {
  final Widget child;

  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
