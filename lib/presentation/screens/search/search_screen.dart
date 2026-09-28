/// Search tab: yt-dlp `ytsearch` listings plus local keyword history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_ui_colors.dart';
import '../../../data/models/browse_video.dart';
import '../../../data/providers/browse_providers.dart';
import '../../../data/providers/library_providers.dart';
import '../../../data/providers/player_provider.dart';
import '../../widgets/browse/browse_video_tile.dart';

/// Search tab.
class SearchScreen extends ConsumerStatefulWidget {
  /// Creates the search tab.
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
    _controller.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onDraftChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    setState(() {});
  }

  Future<void> _submit(String value) async {
    final String trimmed = value.trim();
    ref.read(searchQueryProvider.notifier).state = trimmed;
    if (trimmed.isEmpty) {
      return;
    }
    await ref.read(libraryActionsProvider).saveSearch(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final AppUiColors c = AppColors.of(context);
    final String query = ref.watch(searchQueryProvider);
    final AsyncValue<List<BrowseVideo>> results = ref.watch(
      searchResultsProvider,
    );
    final AsyncValue<List<String>> history = ref.watch(searchHistoryProvider);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text(AppStrings.navSearch)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppDimensions.paddingMd),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: _submit,
              decoration: InputDecoration(
                hintText: AppStrings.searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _controller.clear();
                          _submit('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? _HistoryBody(
                    history: history,
                    filter: _controller.text.trim(),
                    onSelect: (String keyword) {
                      _controller
                        ..text = keyword
                        ..selection = TextSelection.collapsed(
                          offset: keyword.length,
                        );
                      _submit(keyword);
                    },
                    onDelete: (String keyword) {
                      ref.read(libraryActionsProvider).deleteSearch(keyword);
                    },
                  )
                : results.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (Object error, StackTrace stack) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppDimensions.paddingLg),
                        child: Text(
                          AppStrings.errorExtractionBroken,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.error),
                        ),
                      ),
                    ),
                    data: (List<BrowseVideo> videos) {
                      if (videos.isEmpty) {
                        return const Center(
                          child: Text(AppStrings.searchNoResults),
                        );
                      }
                      return ListView.builder(
                        itemCount: videos.length,
                        itemBuilder: (BuildContext context, int index) {
                          final BrowseVideo v = videos[index];
                          return BrowseVideoTile(
                            video: v,
                            onTap: () => ref
                                .read(playerControllerProvider.notifier)
                                .play(v),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.history,
    required this.filter,
    required this.onSelect,
    required this.onDelete,
  });

  final AsyncValue<List<String>> history;
  final String filter;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => const _EmptySearchHint(),
      data: (List<String> items) {
        final String needle = filter.toLowerCase();
        final List<String> visible = needle.isEmpty
            ? items
            : items
                  .where((String q) => q.toLowerCase().contains(needle))
                  .toList();
        if (visible.isEmpty) {
          return const _EmptySearchHint();
        }
        return ListView(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.paddingMd,
                AppDimensions.spaceSm,
                AppDimensions.paddingMd,
                AppDimensions.spaceXs,
              ),
              child: Text(
                AppStrings.recentSearches,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            ...visible.map((String keyword) {
              return ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(keyword),
                onTap: () => onSelect(keyword),
                trailing: IconButton(
                  tooltip: AppStrings.deleteSearchTooltip,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => onDelete(keyword),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _EmptySearchHint extends StatelessWidget {
  const _EmptySearchHint();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppDimensions.paddingLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_rounded, size: 48),
            SizedBox(height: 12),
            Text(AppStrings.searchEmptyTitle),
            SizedBox(height: 4),
            Text(
              AppStrings.searchEmptySubtitle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
