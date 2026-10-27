import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SearchSource { library, online }

/// The selected Search source. Lives in a provider so Home can open Downloads
/// directly while Search keeps the user's tab.
final searchSourceProvider =
    NotifierProvider<SearchSourceNotifier, SearchSource>(
      SearchSourceNotifier.new,
    );

class SearchSourceNotifier extends Notifier<SearchSource> {
  @override
  SearchSource build() => SearchSource.library;

  void set(SearchSource source) => state = source;
}
