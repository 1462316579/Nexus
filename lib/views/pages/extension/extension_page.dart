import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:miru_app/controllers/extension/extension_controller.dart';
import 'package:miru_app/views/widgets/extension/extension_tile.dart';
import 'package:miru_app/views/pages/extension/extension_repo_page.dart';
import 'package:miru_app/router/router.dart';
import 'package:miru_app/utils/extension.dart';
import 'package:miru_app/utils/i18n.dart';
import 'package:miru_app/utils/router.dart';
import 'package:miru_app/views/widgets/button.dart';
import 'package:miru_app/views/widgets/messenger.dart';
import 'package:miru_app/views/widgets/platform_widget.dart';
import 'package:miru_app/views/widgets/extension/extension_type_filter.dart';
import 'package:url_launcher/url_launcher.dart';

class ExtensionPage extends StatefulWidget {
  const ExtensionPage({super.key});

  @override
  State<ExtensionPage> createState() => _ExtensionPageState();
}

class _ExtensionPageState extends State<ExtensionPage> {
  late ExtensionPageController c;
  final _addMenuController = fluent.FlyoutController();

  @override
  void initState() {
    c = Get.put(ExtensionPageController());
    c.isPageOpen = true;
    if (c.needRefresh) {
      c.onRefresh();
    }
    super.initState();
  }

  @override
  void dispose() {
    c.isPageOpen = false;
    super.dispose();
  }

  void _importByUrl() {
    String url = '';
    showPlatformDialog(
      context: context,
      title: 'extension.import.title'.i18n,
      maxWidth: 500,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PlatformWidget(
            androidWidget: TextField(
              decoration: InputDecoration(
                labelText: 'extension.import.url-label'.i18n,
                hintText: "https://example.com/extension.js",
              ),
              onChanged: (value) {
                url = value;
              },
            ),
            desktopWidget: Row(
              children: [
                Expanded(
                    child: fluent.TextBox(
                  placeholder: 'extension.import.url-label'.i18n,
                  onChanged: (value) {
                    url = value;
                  },
                )),
                const SizedBox(width: 8),
                fluent.Tooltip(
                  message: 'extension.import.extension-dir'.i18n,
                  child: fluent.IconButton(
                    icon: const Icon(fluent.FluentIcons.fabric_folder),
                    onPressed: () async {
                      RouterUtils.pop();
                      // 定位目录
                      final dir = ExtensionUtils.extensionsDir;
                      final uri = Uri.directory(dir);
                      await launchUrl(uri);
                    },
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(fluent.FluentIcons.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "extension.import.tips".i18n,
                  softWrap: true,
                ),
              )
            ],
          ),
        ],
      ),
      actions: [
        PlatformButton(
          onPressed: () {
            RouterUtils.pop();
          },
          child: Text('common.cancel'.i18n),
        ),
        PlatformFilledButton(
          onPressed: () async {
            RouterUtils.pop();
            await ExtensionUtils.install(url, context);
          },
          child: Text('extension.import.import-by-url'.i18n),
        ),
      ],
    );
  }

  Future<void> _importByLocal() async {
    // 支持 .js、.json 文件和目录选择
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['js', 'json'],
    );
    if (result == null || !mounted) return;

    int totalInstalled = 0;
    final paths = result.files
        .where((f) => f.path != null)
        .map((f) => f.path!)
        .toList();

    if (paths.isEmpty) return;

    for (final filePath in paths) {
      final ext = filePath.toLowerCase();

      if (ext.endsWith('.json')) {
        // JSON 聚合文件导入
        try {
          final installed = await ExtensionUtils.installByJson(
            filePath,
            context,
          );
          totalInstalled += installed;
        } catch (e) {
          debugPrint('Failed to import JSON: $e');
        }
      } else if (ext.endsWith('.js')) {
        // 单个 JS 文件导入
        try {
          final script = File(filePath).readAsStringSync();
          await ExtensionUtils.installByScript(script, context);
          totalInstalled++;
        } catch (e) {
          debugPrint('Failed to import JS: $e');
        }
      }
    }

    if (totalInstalled > 0 && mounted) {
      showPlatformDialog(
        context: context,
        title: 'extension.installed'.i18n,
        content: Text('Successfully imported $totalInstalled plugin(s)'),
        actions: [
          PlatformButton(
            onPressed: () {
              RouterUtils.pop();
            },
            child: Text('common.close'.i18n),
          ),
        ],
      );
    }
  }

  Future<void> _importByDirectory() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null || !mounted) return;

    try {
      final installed = await ExtensionUtils.installByDirectory(
        dirPath,
        context,
      );

      if (mounted) {
        showPlatformDialog(
          context: context,
          title: 'extension.installed'.i18n,
          content: Text('Successfully imported $installed plugin(s)'),
          actions: [
            PlatformButton(
              onPressed: () {
                RouterUtils.pop();
              },
              child: Text('common.close'.i18n),
            ),
          ],
        );
      }
    } catch (e) {
      debugPrint('Failed to import directory: $e');
    }
  }

  void _showAddMenu() {
    if (Platform.isAndroid) {
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('新建插件'),
                onTap: () {
                  Navigator.pop(context);
                  router.push('/music/new-plugin');
                },
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: Text('extension.import.import-by-url'.i18n),
                onTap: () {
                  Navigator.pop(context);
                  _importByUrl();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('本地导入'),
                onTap: () {
                  Navigator.pop(context);
                  _importByLocal();
                },
              ),
              ListTile(
                leading: const Icon(Icons.filter_list),
                title: Text('common.show-all'.i18n),
                onTap: () {
                  Navigator.pop(context);
                  _filterDialog();
                },
              ),
            ],
          ),
        ),
      );
      return;
    }

    _addMenuController.showFlyout(
      autoModeConfiguration: fluent.FlyoutAutoConfiguration(
        preferredMode: fluent.FlyoutPlacementMode.bottomRight,
      ),
      builder: (context) => fluent.MenuFlyout(
        items: [
          fluent.MenuFlyoutItem(
            leading: const Icon(fluent.FluentIcons.edit),
            text: const Text('新建插件'),
            onPressed: () {
              fluent.Flyout.of(context).close();
              router.push('/music/new-plugin');
            },
          ),
          fluent.MenuFlyoutItem(
            leading: const Icon(fluent.FluentIcons.link),
            text: Text('extension.import.import-by-url'.i18n),
            onPressed: () {
              fluent.Flyout.of(context).close();
              _importByUrl();
            },
          ),
          fluent.MenuFlyoutItem(
            leading: const Icon(fluent.FluentIcons.fabric_folder),
            text: const Text('本地导入'),
            onPressed: () {
              fluent.Flyout.of(context).close();
              _importByLocal();
            },
          ),
        ],
      ),
      barrierDismissible: true,
      dismissWithEsc: true,
    );
  }

  // 筛选对话框
  _filterDialog() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Obx(
            () => ExtensionTypeFilter(
              selectedType: c.searchType.value,
              onTypeChanged: (type) {
                c.searchType.value = type;
              },
              compact: true,
            ),
          ),
        );
      },
    );
  }

  // 加载错误对话框
  _loadErrorDialog() {
    showPlatformDialog(
      context: context,
      title: 'extension.error-dialog'.i18n,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 输出key 和 value
            for (final e in c.errors.entries)
              PlatformWidget(
                androidWidget: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "${e.key}: ${e.value}",
                    ),
                  ),
                ),
                desktopWidget: fluent.Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    "${e.key}: ${e.value}",
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        PlatformButton(
          onPressed: () {
            RouterUtils.pop();
          },
          child: Text('common.confirm'.i18n),
        ),
      ],
    );
  }

  Widget _buildAndroid(BuildContext context) {
    return Obx(() {
      return Scaffold(
        appBar: AppBar(
          title: Text('common.extension'.i18n),
          actions: [
            if (c.errors.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.error),
                onPressed: () => _loadErrorDialog(),
              ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _filterDialog(),
            ),
            IconButton(
              onPressed: _showAddMenu,
              icon: const Icon(Icons.add),
            ),
            IconButton(
              onPressed: () {
                Get.to(
                  () => const ExtensionRepoPage(),
                );
              },
              icon: const Icon(Icons.download),
            )
          ],
        ),
        body: _buildExtensionList(),
      );
    });
  }

  Widget _buildExtensionList() {
    // 过滤扩展
    var extensions = c.runtimes.values.toList();
    if (c.searchType.value != null) {
      extensions = extensions
          .where((ext) => ext.extension.type == c.searchType.value)
          .toList();
    }

    return ListView(
      children: [
        if (extensions.isEmpty)
          SizedBox(
            height: 300,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('common.no-extension'.i18n),
              ],
            ),
          ),
        for (final ext in extensions) ExtensionTile(ext.extension),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Obx(
        () => Column(
          children: [
            Row(
              children: [
                Text(
                  'common.extension'.i18n,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // 筛选按钮
                ExtensionTypeFilter(
                  selectedType: c.searchType.value,
                  onTypeChanged: (type) {
                    c.searchType.value = type;
                  },
                ),
                const SizedBox(width: 16),
                // 错误按钮
                if (c.errors.isNotEmpty)
                  fluent.IconButton(
                    icon: const Icon(fluent.FluentIcons.error),
                    onPressed: () {
                      _loadErrorDialog();
                    },
                  ),
                fluent.FlyoutTarget(
                  controller: _addMenuController,
                  child: fluent.IconButton(
                    icon: const Icon(fluent.FluentIcons.add),
                    onPressed: _showAddMenu,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _buildExtensionList(),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlatformBuildWidget(
      androidBuilder: _buildAndroid,
      desktopBuilder: _buildDesktop,
    );
  }
}
