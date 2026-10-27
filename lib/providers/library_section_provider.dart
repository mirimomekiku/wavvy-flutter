import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The sections of the Library tab (toggle chips).
enum LibrarySection { songs, albums, artists, playlists }

/// Which Library section is showing. Lives in a provider so other tabs (for
/// example Home's "Show all albums") can switch it before navigating to the
/// Library tab.
final librarySectionProvider =
    NotifierProvider<LibrarySectionNotifier, LibrarySection>(
      LibrarySectionNotifier.new,
    );

class LibrarySectionNotifier extends Notifier<LibrarySection> {
  @override
  LibrarySection build() => LibrarySection.songs;

  void set(LibrarySection section) => state = section;
}
