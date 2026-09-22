import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:miru_app/controllers/search_controller.dart';
import 'package:miru_app/models/extension.dart';
import 'package:miru_app/views/widgets/extension_item_card.dart';
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
  }

  @override
  void dispose() {
    controller.isPageOpen = false;
    Get.delete<SearchPageController>(tag: controllerTag);
    searchController.dispose();
    super.dispose();
  }

  SearchResult? get selectedResult {
    if (controller.searchResultList.isEmpty) return null;
    selectedPackage ??= controller.searchResultList.first.runitme.extension.package;
    return controller.searchResultList.firstWhere(
      (item) => item.runitme.extension.package == selectedPackage,
      orElse: () => controller.searchResultList.first,
    );
  }

  void submitSearch(String value) {
    controller.search.value = value.trim();
  }

  void selectPlugin(SearchResult result) {
    setState(() {
      selectedPackage = result.runitme.extension.package;
    });
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
                    ? fluent.FluentTheme.of(context).accentColor.withValues(alpha: 0.18)
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

  Widget _content(BuildContext context) {
    final result = selectedResult;
    if (result == null) return const Center(child: Text('暂无可用插件'));
    if (result.error != null) return Center(child: Text(result.error!));
    if (result.result == null) return const Center(child: CircularProgressIndicator());
    if (result.result!.isEmpty) return const Center(child: Text('暂无内容'));

    final list = LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        key: ValueKey(result.runitme.extension.package),
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (constraints.maxWidth / 160).floor().clamp(1, 8),
          childAspectRatio: 0.6,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: result.result!.length,
        itemBuilder: (context, index) {
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

    return Container(
      color: fluent.FluentTheme.of(context).scaffoldBackgroundColor,
      child: Material(
        type: MaterialType.transparency,
        child: list,
      ),
    );
  }

  Widget _desktop(BuildContext context) => Obx(
        () => Container(
          color: fluent.FluentTheme.of(context).scaffoldBackgroundColor,
          child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(children: [
              Text(widget.title, style: fluent.FluentTheme.of(context).typography.title),
              const Spacer(),
              SizedBox(width: 320, child: _searchBox()),
            ]),
          ),
          _pluginBar(true),
          if (controller.searchResultList.isNotEmpty &&
              controller.finishCount != controller.searchResultList.length)
            const fluent.ProgressBar(),
          Expanded(
            child: Container(
              color: fluent.FluentTheme.of(context).scaffoldBackgroundColor,
              child: _content(context),
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
              Expanded(child: _content(context)),
            ])),
      );

  @override
  Widget build(BuildContext context) => PlatformBuildWidget(
        androidBuilder: _android,
        desktopBuilder: _desktop,
      );
}
