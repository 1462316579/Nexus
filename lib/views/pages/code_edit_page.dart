import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:miru_app/data/services/plugin_ai_service.dart';
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
  final TextEditingController _aiInput = TextEditingController();
  final List<Map<String, dynamic>> _aiMessages = [];
  InAppWebViewController? _browserController;
  String? _browserUrl;
  bool _aiBusy = false;
  bool _showBrowser = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    controller.dispose();
    _aiInput.dispose();
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

  Future<String> _openBrowser(String url) async {
    setState(() {
      _showBrowser = true;
      _browserUrl = url;
    });
    for (var i = 0; i < 30; i++) {
      final webController = _browserController;
      if (webController != null) {
        if (_browserUrl != url) {
          await webController.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
        }
        for (var attempt = 0; attempt < 30; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final current = await webController.getUrl();
          if (current?.toString() == url) break;
        }
        final result = await webController.evaluateJavascript(
          source: 'document.body?.innerText || ""',
        );
        return result?.toString() ?? '';
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('内置浏览器尚未就绪');
  }

  Future<void> _sendAi() async {
    final prompt = _aiInput.text.trim();
    if (prompt.isEmpty || _aiBusy) return;
    setState(() {
      _aiBusy = true;
      _aiMessages.add({'role': 'user', 'content': prompt});
    });
    _aiInput.clear();
    if (_aiMessages.isEmpty) {
      _aiMessages.add({
        'role': 'system',
        'content':
            '你是 Miru 插件开发助手。协助编写当前 JavaScript 插件。当前代码如下：\\n${controller.text}\\n可调用 browser_open(url) 在编辑器内置浏览器打开网页并读取页面文本。需要修改代码时用 JavaScript 代码围栏返回完整代码。',
      });
    }
    try {
      final reply = await PluginAiService.chat(
        messages: _aiMessages,
        openBrowser: _openBrowser,
      );
      if (mounted) {
        setState(
            () => _aiMessages.add({'role': 'assistant', 'content': reply}));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _aiMessages
            .add({'role': 'assistant', 'content': 'AI 请求失败：$error'}));
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _applyAiCode(String content) {
    final match =
        RegExp(r'```(?:javascript|js)?\s*([\s\S]*?)```', caseSensitive: false)
            .firstMatch(content);
    if (match != null) controller.text = match.group(1)!.trim();
  }

  Widget _aiPanel() => SizedBox(
        height: 250,
        child: Column(
          children: [
            if (_showBrowser) SizedBox(height: 130, child: _browserPanel()),
            Expanded(
              child: ListView.builder(
                itemCount: _aiMessages.length,
                itemBuilder: (context, index) {
                  final message = _aiMessages[index];
                  final content = message['content']?.toString() ?? '';
                  return ListTile(
                    dense: true,
                    title: Text(message['role'] == 'user' ? '你' : 'AI'),
                    subtitle: SelectableText(content),
                    trailing: message['role'] == 'assistant' &&
                            content.contains('```')
                        ? IconButton(
                            tooltip: '应用代码',
                            onPressed: () => _applyAiCode(content),
                            icon: const Icon(Icons.code),
                          )
                        : null,
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _aiInput,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '描述插件需求，AI 可按需浏览网页',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendAi(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '发送给 AI',
                  onPressed: _aiBusy ? null : _sendAi,
                  icon: _aiBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _browserPanel() => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_browserUrl ?? '内置浏览器'),
              ),
              IconButton(
                tooltip: '关闭浏览器',
                onPressed: () => setState(() => _showBrowser = false),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: _browserUrl == null
                  ? null
                  : URLRequest(url: WebUri(_browserUrl!)),
              onWebViewCreated: (webController) {
                _browserController = webController;
              },
              onLoadStop: (controller, url) {
                if (url != null && mounted) {
                  setState(() => _browserUrl = url.toString());
                }
              },
            ),
          ),
        ],
      );

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
        body: Column(children: [Expanded(child: _editor()), _aiPanel()]),
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
      content: Column(children: [Expanded(child: _editor()), _aiPanel()]),
    );
  }
}
