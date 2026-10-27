import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/downloader/flavor.dart';
import 'package:wavvy/downloader/models.dart';
import 'package:wavvy/downloader/search_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/providers/search_source_provider.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/screens/downloader/downloads_sheet.dart';
import 'package:wavvy/screens/search/library_results.dart';
import 'package:wavvy/screens/search/online_results.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

// The Online entries are behind the build flag so that the Play build contains
// none of the downloader's code or text.
const _labels = {
  SearchSource.library: 'Library',
  if (kDownloaderAvailable) SearchSource.online: 'Online',
};

const _icons = {
  SearchSource.library: Icons.library_music_rounded,
  if (kDownloaderAvailable) SearchSource.online: Icons.public_rounded,
};

const _hints = {
  SearchSource.library: 'Songs, albums, artists',
  if (kDownloaderAvailable)
    SearchSource.online: 'Search online or paste a link',
};

/// The Search tab: local library search, and (in builds with the downloader)
/// online search and downloads through yt-dlp.
class SearchTab extends ConsumerStatefulWidget {
  const SearchTab({super.key});

  @override
  ConsumerState<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<SearchTab> {
  final TextEditingController _controller = TextEditingController();
  final Map<SearchSource, String> _drafts = {};
  SearchSource get _source => ref.read(searchSourceProvider);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(SearchSource source) {
    if (source != _source) {
      ref.read(searchSourceProvider.notifier).set(source);
    }
  }

  void _submit(SearchSource source, String value) {
    final q = value.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    if (kDownloaderAvailable) {
      if (source == SearchSource.online) {
        ref.read(onlineSearchProvider.notifier).submit(q);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      settingsProvider.select((s) => s.enableDownloader),
    );
    final selectedSource = ref.watch(searchSourceProvider);
    ref.listen(searchSourceProvider, (previous, next) {
      if (previous != null) _drafts[previous] = _controller.text;
      _controller.text = _drafts[next] ?? '';
      setState(() {});
    });
    ref.listen(settingsProvider.select((s) => s.enableDownloader), (
      _,
      allowed,
    ) {
      if (!allowed && _source != SearchSource.library) {
        _select(SearchSource.library);
      }
    });
    final sources = kDownloaderAvailable && enabled
        ? SearchSource.values
        : const [SearchSource.library];
    // Fall back to Library without touching any provider.
    final source = sources.contains(selectedSource)
        ? selectedSource
        : SearchSource.library;
    final query = _controller.text;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: WvPageHeading(
            title: 'Search',
            subtitle: 'Find music. Build your collection.',
            settings: true,
            actions: [
              if (kDownloaderAvailable)
                if (enabled)
                  IconButton(
                    tooltip: 'Downloads',
                    onPressed: () => showDownloadsSheet(context),
                    icon: const Icon(Icons.download_rounded),
                  ),
            ],
            // Source icons live in the heading; one source needs no chooser.
            bottom: kDownloaderAvailable
                ? (enabled
                      ? WvChips(
                          labels: [for (final s in sources) _labels[s]!],
                          icons: [for (final s in sources) _icons[s]!],
                          selected: sources.indexOf(source),
                          onChanged: (i) => _select(sources[i]),
                        )
                      : null)
                : null,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Field(
              controller: _controller,
              hint: _hints[source]!,
              icon: kDownloaderAvailable
                  ? (source == SearchSource.online &&
                            MediaInfo.looksLikeUrl(query)
                        ? Icons.link_rounded
                        : Icons.search_rounded)
                  : Icons.search_rounded,
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) => _submit(source, v),
              onClear: () => setState(_controller.clear),
              onSearch: kDownloaderAvailable
                  ? (source == SearchSource.online
                        ? () => _submit(source, _controller.text)
                        : null)
                  : null,
              onPaste: kDownloaderAvailable && source == SearchSource.online
                  ? () async {
                      final clip = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (!mounted) return;
                      setState(
                        () => _controller.text = clip?.text?.trim() ?? '',
                      );
                    }
                  : null,
            ),
          ),
        ),
        switch (source) {
          SearchSource.library => LibraryResults(query: query),
          SearchSource.online =>
            kDownloaderAvailable
                ? const OnlineResults()
                : const SliverToBoxAdapter(),
        },
        SliverToBoxAdapter(
          child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback? onSearch;
  final VoidCallback? onPaste;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    this.onSearch,
    this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);

    return AquaSearchFrame(
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(icon, size: 19, color: a.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: false,
              textInputAction: TextInputAction.search,
              cursorColor: a.accent,
              style: TextStyle(fontSize: 14, color: a.text),
              decoration: aquaSearchDecoration(context, hint: hint),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: onClear,
              icon: Icon(
                Icons.cancel_rounded,
                size: 18,
                color: a.textSecondary,
              ),
            ),
          if (onPaste != null && controller.text.isEmpty)
            IconButton(
              tooltip: 'Paste link',
              onPressed: onPaste,
              icon: const Icon(Icons.content_paste_rounded, size: 20),
            ),
          if (onSearch != null && controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Submit search',
              onPressed: onSearch,
              icon: Icon(Icons.arrow_forward_rounded, color: a.accent),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
