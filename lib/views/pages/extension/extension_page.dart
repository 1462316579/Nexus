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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['js'],
    );
    if (result == null || !mounted) return;
    final path = result.files.single.path;
    if (path == null) return;
    final script = File(path).readAsStringSync();
    await ExtensionUtils.installByScript(script, context);
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
        body: ListView(
          children: [
            if (c.runtimes.isEmpty)
              SizedBox(
                height: 300,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('common.no-extension'.i18n),
                  ],
                ),
              ),
            for (final ext in c.runtimes.values) ExtensionTile(ext.extension),
          ],
        ),
      );
    });
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
            if (c.runtimes.isEmpty)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('common.no-extension'.i18n),
                    const SizedBox(height: 8),
                    fluent.FilledButton(
                      child: Text(
                        'common.extension-repo'.i18n,
                      ),
                      onPressed: () {
                        router.push('/extension_repo');
                      },
                    )
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final ext in c.runtimes.values)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExtensionTile(ext.extension),
                    ),
                ],
              ),
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
