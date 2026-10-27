import 'package:flutter/material.dart';
import 'package:wavvy/screens/search/downloads_list.dart';
import 'package:wavvy/theme/aqua_widgets.dart';
import 'package:wavvy/theme/wavvy_widgets.dart';

/// Opens the download history as a full-screen sheet: a title bar with the
/// close light, a search field, the All / Active / Completed / Failed filter
/// and the task list.
Future<void> showDownloadsSheet(BuildContext context) {
  return showAquaSheet<void>(
    context: context,
    title: 'Downloads',
    fullScreen: true,
    builder: (_) => const _DownloadsBody(),
  );
}

class _DownloadsBody extends StatefulWidget {
  const _DownloadsBody();

  @override
  State<_DownloadsBody> createState() => _DownloadsBodyState();
}

class _DownloadsBodyState extends State<_DownloadsBody> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = Wv.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: AquaSearchFrame(
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 14),
                decoration: aquaSearchDecoration(
                  context,
                  hint: 'Search downloads',
                  prefix: Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: a.textSecondary,
                  ),
                  suffix: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: Icon(
                            Icons.cancel_rounded,
                            size: 18,
                            color: a.textSecondary,
                          ),
                          onPressed: () => setState(_query.clear),
                        ),
                ),
              ),
            ),
          ),
        ),
        DownloadsList(query: _query.text),
        SliverToBoxAdapter(
          child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
  }
}
