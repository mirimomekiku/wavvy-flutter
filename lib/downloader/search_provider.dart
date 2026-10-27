import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/downloader/engine.dart';
import 'package:wavvy/downloader/engine_provider.dart';
import 'package:wavvy/downloader/models.dart';

class OnlineSearchState {
  final String query;
  final bool isLoading;
  final bool hasSearched;
  final List<MediaInfo> results;
  final String error;

  const OnlineSearchState({
    this.query = '',
    this.isLoading = false,
    this.hasSearched = false,
    this.results = const [],
    this.error = '',
  });
}

final onlineSearchProvider =
    NotifierProvider<OnlineSearchNotifier, OnlineSearchState>(
      OnlineSearchNotifier.new,
    );

/// Online search: a link is looked up as one item, anything else is searched
/// on YouTube. A slow answer for an older request never replaces a newer one.
class OnlineSearchNotifier extends Notifier<OnlineSearchState> {
  int _request = 0;

  @override
  OnlineSearchState build() {
    ref.onDispose(() => _request++);
    return const OnlineSearchState();
  }

  YtDlpEngine get _engine => ref.read(ytDlpEngineProvider);

  Future<void> submit(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final request = ++_request;
    state = OnlineSearchState(query: q, isLoading: true, hasSearched: true);
    try {
      final results = MediaInfo.looksLikeUrl(q)
          ? [await _engine.resolve(q)]
          : await _engine.search(q);
      if (request != _request) return;
      state = OnlineSearchState(
        query: q,
        hasSearched: true,
        results: results.where((r) => r.id.isNotEmpty).toList(),
      );
    } on DownloaderException catch (e) {
      if (request != _request) return;
      state = OnlineSearchState(query: q, hasSearched: true, error: e.message);
    }
  }

  void clear() {
    _request++;
    state = const OnlineSearchState();
  }
}
