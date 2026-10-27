import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SearchSource { library, youtube, tiktok, downloads }

/// Lets Home open downloads directly while retaining the user's search tab.
final searchSourceProvider = StateProvider<SearchSource>(
  (ref) => SearchSource.library,
);
