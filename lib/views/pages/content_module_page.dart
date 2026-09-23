import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:miru_app/controllers/search_controller.dart';
import 'package:miru_app/models/extension.dart';
import 'package:miru_app/views/widgets/extension_item_card.dart';
import 'package:miru_app/views/widgets/infinite_scroller.dart';
import 'package:miru_app/views/widgets/platform_widget.dart';

class ContentModulePage extends StatefulWidget {
  const ContentModulePage({super.key, required this.type, required this.title});

  final ExtensionType type;
  final String title;

  @override
  State<ContentModulePage> createState() => _ContentModulePageState();
}

class _ContentModulePageState extends State<ContentModulePage> {
  late final SearchPageController controller;
  late final String controllerTag;
  late final TextEditingController searchController;
  String? selectedPackage;
  bool _filtersExpanded = false;
  final ScrollController _contentScrollController = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    controllerTag = 'content-module-${widget.type.name}';
    controller = Get.isRegistered<SearchPageController>(tag: controllerTag)
        ? Get.find<SearchPageController>(tag: controllerTag)
        : Get.put(SearchPageController(), tag: controllerTag);
    controller.isPageOpen = true;
    searchController = TextEditingController(text: controller.search.value);
    controller.getRuntime(type: widget.type, prioritizeResults: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final result = selectedResult;
      if (result != null) _loadFilters(result);
    });
  }

  @override
  void dispose() {
    controller.isPageOpen = false;
    Get.delete<SearchPageController>(tag: controllerTag);
    _contentScrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  SearchResult? get selectedResult {
    if (controller.searchResultList.isEmpty) return null;
    selectedPackage ??=
        controller.searchResultList.first.runitme.extension.package;
    return controller.searchResultList.firstWhere(
      (item) => item.runitme.extension.package == selectedPackage,
      orElse: () => controller.searchResultList.first,
    );
  }

  void submitSearch(String value) {
    selectedResult?.selectedFilters.clear();
    selectedResult?.filters = null;
    controller.search.value = value.trim();
  }

  void selectPlugin(SearchResult result) {
    setState(() {
      selectedPackage = result.runitme.extension.package;
    });
    if (result.filters == null) _loadFilters(result);
  }

  Future<void> _loadFilters(SearchResult result) async {
    try {
      await controller.loadFilters(result);
    } catch (error) {
      result.error = error.toString();
      controller.searchResultList.refresh();
    }
  }

  Future<void> _toggleFilter(
    SearchResult result,
    String key,
    String value,
  ) async {
    final filter = result.filters![key]!;
    final selected = List<String>.from(result.selectedFilters[key] ?? []);
    if (selected.contains(value)) {
      if (selected.length > filter.min) selected.remove(value);
    } else {
      if (filter.max == 1) selected.clear();
      if (selected.length < filter.max) selected.add(value);
    }
    final updated = {
      for (final entry in result.selectedFilters.entries)
        entry.key: List<String>.from(entry.value),
      key: selected,
    };
    await controller.applyFilters(result, updated);
    await _loadFilters(result);
  }

  Widget _filtersBar() {
    final result = selectedResult;
    if (result == null || result.filters == null || result.filters!.isEmpty) {
      return const SizedBox.shrink();
    }
    final groups = result.filters!.entries
        .where((entry) => entry.value.options.isNotEmpty)
        .toList();
    if (groups.isEmpty) return const SizedBox.shrink();
    final visibleCount =
        _filtersExpanded ? groups.length : groups.length.clamp(0, 2);
    const rowHeight = 38.0;
    final showToggle = groups.length > 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in groups.take(visibleCount))
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      entry.value.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: entry.value.options.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        final option =
                            entry.value.options.entries.elementAt(index);
                        final selected =
                            (result.selectedFilters[entry.key] ?? [])
                                .contains(option.key);
                        return PlatformBuildWidget(
                          androidBuilder: (_) => ChoiceChip(
                            label: Text(option.value),
                            selected: selected,
                            onSelected: (_) =>
                                _toggleFilter(result, entry.key, option.key),
                            visualDensity: VisualDensity.compact,
                          ),
                          desktopBuilder: (_) => fluent.ToggleButton(
                            checked: selected,
                            onChanged: (_) =>
                                _toggleFilter(result, entry.key, option.key),
                            child: Text(option.value),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (showToggle)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _filtersExpanded = !_filtersExpanded),
                icon: Icon(
                    _filtersExpanded ? Icons.expand_less : Icons.expand_more),
                label: Text(_filtersExpanded ? '收起分类' : '展开全部分类'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchBox() => fluent.TextBox(
        controller: searchController,
        placeholder: '搜索${widget.title}',
        suffix: fluent.IconButton(
          icon: const Icon(fluent.FluentIcons.chrome_close, size: 10),
          onPressed: () {
            searchController.clear();
            submitSearch('');
          },
        ),
        onSubmitted: submitSearch,
      );

  Widget _pluginBar(bool desktop) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: controller.searchResultList.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final result = controller.searchResultList[index];
          final selected = result.runitme.extension.package == selectedPackage;
          return GestureDetector(
            onTap: () => selectPlugin(result),
            child: Container(
              constraints: const BoxConstraints(minWidth: 72, maxWidth: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? fluent.FluentTheme.of(context)
                        .accentColor
                        .withValues(alpha: 0.18)
                    : fluent.FluentTheme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
              ),
              child: Text(
                result.runitme.extension.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _contentSliver(BuildContext context) {
    final result = selectedResult;
    if (result == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('暂无可用插件')),
      );
    }
    if (result.error != null && result.result == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text(result.error!)),
      );
    }
    if (result.result == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (result.result!.isEmpty && !result.loadingMore) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: Text('暂无内容')),
      );
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.crossAxisExtent / 160).floor().clamp(1, 8);
        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid.builder(
            key: ValueKey(result.runitme.extension.package),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 0.6,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: result.result!.length + (result.loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= result.result!.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final item = result.result![index];
              return ExtensionItemCard(
                key: ValueKey(item.url),
                title: item.title,
                url: item.url,
                package: result.runitme.extension.package,
                cover: item.cover,
                update: item.update,
                headers: item.headers,
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _scrollToTop() async {
    if (!_contentScrollController.hasClients) return;
    await _contentScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _contentViewport() => NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical) {
            final show = notification.metrics.pixels > 500;
            if (show != _showBackToTop && mounted) {
              setState(() => _showBackToTop = show);
            }
          }
          return false;
        },
        child: Stack(
          children: [
            CustomScrollView(
              controller: _contentScrollController,
              slivers: [
                SliverToBoxAdapter(child: _filtersBar()),
                _contentSliver(context),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: AnimatedScale(
                scale: _showBackToTop ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  ignoring: !_showBackToTop,
                  child: Tooltip(
                    message: '回到顶部',
                    child: FloatingActionButton.small(
                      heroTag: 'back-to-top-${widget.type.name}',
                      onPressed: _scrollToTop,
                      child: const Icon(Icons.arrow_upward),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _desktop(BuildContext context) => Obx(
        () => Container(
          color: fluent.FluentTheme.of(context).scaffoldBackgroundColor,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(children: [
                Text(widget.title,
                    style: fluent.FluentTheme.of(context).typography.title),
                const Spacer(),
                SizedBox(width: 320, child: _searchBox()),
              ]),
            ),
            _pluginBar(true),
            if (controller.searchResultList.isNotEmpty &&
                controller.finishCount != controller.searchResultList.length)
              const fluent.ProgressBar(),
            Expanded(
              child: InfiniteScroller(
                refreshOnStart: false,
                onRefresh: () async {},
                onLoad: () async {
                  final result = selectedResult;
                  if (result != null) await controller.loadMore(result);
                },
                child: _contentViewport(),
              ),
            ),
          ]),
        ),
      );

  Widget _android(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: searchController,
                onSubmitted: submitSearch,
                decoration: InputDecoration(hintText: '搜索${widget.title}'),
              ),
            ),
          ),
        ),
        body: Obx(() => Column(children: [
              _pluginBar(false),
              Expanded(
                child: InfiniteScroller(
                  refreshOnStart: false,
                  onRefresh: () async {},
                  onLoad: () async {
                    final result = selectedResult;
                    if (result != null) await controller.loadMore(result);
                  },
                  child: _contentViewport(),
                ),
              ),
            ])),
      );

  @override
  Widget build(BuildContext context) => PlatformBuildWidget(
        androidBuilder: _android,
        desktopBuilder: _desktop,
      );
}
