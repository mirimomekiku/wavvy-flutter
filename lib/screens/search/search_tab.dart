import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavvy/providers/downloads_provider.dart';
import 'package:wavvy/providers/settings_provider.dart';
import 'package:wavvy/providers/search_source_provider.dart';
import 'package:wavvy/widgets/page_heading.dart';
import 'package:wavvy/screens/search/downloads_list.dart';
import 'package:wavvy/screens/search/library_results.dart';
import 'package:wavvy/screens/search/tiktok_panel.dart';
import 'package:wavvy/screens/search/youtube_results.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

const _labels = {
  SearchSource.library: 'Library',
  SearchSource.youtube: 'YouTube',
  SearchSource.tiktok: 'TikTok',
  SearchSource.downloads: 'Downloads',
};

const _hints = {
  SearchSource.library: 'Songs, albums, artists',
  SearchSource.youtube: 'Search YouTube',
  SearchSource.tiktok: 'Paste a TikTok link',
  SearchSource.downloads: 'Search downloads',
};

/// The Search tab: local library search unified with the YouTube / TikTok
/// downloader.
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
      ref.read(searchSourceProvider.notifier).state = source;
    }
  }

  void _submit(SearchSource source, String value) {
    final q = value.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    if (source == SearchSource.youtube) {
      ref.read(ytdlpProvider.notifier).search(q);
    } else if (source == SearchSource.tiktok) {
      ref.read(tiktokProvider.notifier).fetchVideoInfo(q);
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
    final sources = enabled
        ? SearchSource.values
        : const [SearchSource.library];
    // Fall back to Library without touching any provider.
    final source = sources.contains(selectedSource)
        ? selectedSource
        : SearchSource.library;
    final query = _controller.text;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(
          child: WvPageHeading(
            title: 'Search',
            subtitle: 'Find music. Build your collection.',
            settings: true,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Field(
              controller: _controller,
              hint: _hints[source]!,
              icon: source == SearchSource.tiktok
                  ? Icons.link_rounded
                  : Icons.search_rounded,
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) => _submit(source, v),
              onClear: () => setState(_controller.clear),
              onSearch:
                  source == SearchSource.youtube ||
                      source == SearchSource.tiktok
                  ? () => _submit(source, _controller.text)
                  : null,
              onPaste: source == SearchSource.tiktok
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
        if (enabled)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: WvChips(
                labels: [for (final s in sources) _labels[s]!],
                selected: sources.indexOf(source),
                uppercase: true,
                indicator: true,
                onChanged: (i) => _select(sources[i]),
              ),
            ),
          ),
        switch (source) {
          SearchSource.library => LibraryResults(query: query),
          SearchSource.youtube => const YoutubeResults(),
          SearchSource.tiktok => TikTokPanel(
            onFetch: () => _submit(SearchSource.tiktok, _controller.text),
            onDownloadStarted: () => setState(_controller.clear),
          ),
          SearchSource.downloads => DownloadsList(query: query),
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

    // Material 3 search bar look: a tall pill with a real TextField inside.
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.only(left: 18),
      decoration: a.frame(color: a.surface, radius: 12, raised: false),
      child: Row(
        children: [
          Icon(icon, size: 24, color: a.accent),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: false,
              textInputAction: TextInputAction.search,
              cursorColor: a.accent,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: a.text,
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14, color: a.textSecondary),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          if (controller.text.isNotEmpty)
            WvButton(
              circular: true,
              size: 40,
              tooltip: 'Clear',
              onPressed: onClear,
              child: Icon(Icons.close_rounded, color: a.textSecondary),
            )
          else
            const SizedBox(width: 18),
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
