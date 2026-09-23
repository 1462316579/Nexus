import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:miru_app/models/extension.dart';
import 'package:miru_app/utils/extension.dart';
import 'package:miru_app/views/widgets/messenger.dart';

class CodeEditPage extends StatefulWidget {
  const CodeEditPage({
    this.extension,
    this.initialCode,
    this.newPlugin = false,
    super.key,
  });

  final Extension? extension;
  final String? initialCode;
  final bool newPlugin;

  @override
  State<CodeEditPage> createState() => _CodeEditPageState();
}

class _CodeEditPageState extends State<CodeEditPage> {
  final CodeController controller = CodeController(language: javascript);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (widget.initialCode != null) {
      controller.text = widget.initialCode!;
      return;
    }
    final extension = widget.extension;
    if (extension == null) return;
    final file =
        File('${ExtensionUtils.extensionsDir}/${extension.package}.js');
    if (await file.exists() && mounted) {
      controller.text = await file.readAsString();
    }
  }

  Future<void> _save() async {
    if (widget.newPlugin) {
      await ExtensionUtils.installByScript(controller.text, context);
      return;
    }
    final extension = widget.extension;
    if (extension == null) return;
    final file =
        File('${ExtensionUtils.extensionsDir}/${extension.package}.js');
    await file.writeAsString(controller.text);
    if (mounted) {
      showPlatformSnackbar(context: context, title: '保存代码', content: '保存成功');
    }
  }

  Widget _editor() => CodeTheme(
        data: CodeThemeData(styles: monokaiSublimeTheme),
        child: SingleChildScrollView(child: CodeField(controller: controller)),
      );

  @override
  Widget build(BuildContext context) {
    final title = widget.newPlugin ? '新建插件' : (widget.extension?.name ?? '');
    if (Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(onPressed: _save, icon: const Icon(Icons.save)),
          ],
        ),
        body: Column(children: [Expanded(child: _editor())]),
      );
    }

    return fluent.ScaffoldPage(
      header: fluent.PageHeader(
        title: Text(title),
        commandBar: fluent.Tooltip(
          message: '保存代码',
          child: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.save),
            onPressed: _save,
          ),
        ),
      ),
      content: _editor(),
    );
  }
}
