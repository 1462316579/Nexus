import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:miru_app/data/services/extension_service.dart';
import 'package:miru_app/data/services/plugin_ai_service.dart';
import 'package:miru_app/utils/extension.dart';
import 'package:miru_app/views/widgets/messenger.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  final InAppWebViewKeepAlive _keepAlive = InAppWebViewKeepAlive();
  InAppWebViewController? _browserController;
  String? _browserUrl;
  String? _selectedPackage;
  String? _pendingPackage;
  String? _pendingCode;
  String? _pendingSummary;
  bool _busy = false;
  bool _showBrowser = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<ExtensionService> get _extensions =>
      ExtensionUtils.runtimes.values.toList();

  ExtensionService? get _selectedExtension {
    if (_extensions.isEmpty) return null;
    final package = _selectedPackage;
    if (package == null) return null;
    for (final runtime in _extensions) {
      if (runtime.extension.package == package) return runtime;
    }
    return null;
  }

  List<Map<String, dynamic>> _conversation() {
    final target = _selectedPackage == null
        ? '当前未指定插件，只能创建新插件。'
        : '用户指定修改包名为 $_selectedPackage 的插件，不要修改其他插件。';
    return [
      {
        'role': 'system',
        'content':
            '你是 Miru 插件开发助手。$target 先使用 list_extensions 了解已安装插件；读取或修改已有插件时必须使用 read_extension 获取最新代码。修改和创建时调用 propose_extension，提供完整可运行代码和正确 MiruExtension 元数据。此工具只会生成待确认代码，不会自动保存。可调用 browser_open 查阅网站。',
      },
      ..._messages.where((message) => message['role'] != 'system'),
    ];
  }

  Future<List<Map<String, dynamic>>> _listExtensions() async {
    final result = <Map<String, dynamic>>[];
    for (final runtime in _extensions) {
      final extension = runtime.extension;
      final file =
          File('${ExtensionUtils.extensionsDir}/${extension.package}.js');
      result.add({
        'package': extension.package,
        'name': extension.name,
        'type': extension.type.name,
        'website': extension.webSite,
        'source': await file.readAsString(),
      });
    }
    return result;
  }

  Future<String> _readExtension(String package) async {
    final runtime = ExtensionUtils.runtimes[package];
    if (runtime == null) return '没有找到包名为 $package 的已安装插件。';
    final file = File('${ExtensionUtils.extensionsDir}/$package.js');
    return file.readAsString();
  }

  Future<void> _proposeExtension({
    required String package,
    required String code,
    required String summary,
  }) async {
    final extension = ExtensionUtils.parseExtension(code);
    if (extension.package != package) {
      throw FormatException('代码元数据包名 ${extension.package} 与提案包名 $package 不一致');
    }
    if (_selectedPackage != null && package != _selectedPackage) {
      throw StateError('当前指定插件为 $_selectedPackage，拒绝修改其他插件');
    }
    if (_selectedPackage == null &&
        ExtensionUtils.runtimes.containsKey(package)) {
      throw StateError('当前为新建插件模式，包名 $package 已存在；请先选择该插件进行修改');
    }
    if (!mounted) return;
    setState(() {
      _pendingPackage = package;
      _pendingCode = code;
      _pendingSummary = summary;
    });
  }

  Future<String> _openBrowser(String url) async {
    if (mounted) {
      setState(() {
        _showBrowser = true;
        _browserUrl = url;
      });
    }
    for (var i = 0; i < 40; i++) {
      final browser = _browserController;
      if (browser != null) {
        if (_browserUrl != url) {
          await browser.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
        }
        for (var attempt = 0; attempt < 40; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          if ((await browser.getUrl())?.toString() == url) break;
        }
        return (await browser.evaluateJavascript(
              source: 'document.body?.innerText || ""',
            ))
                ?.toString() ??
            '';
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('内置浏览器尚未就绪');
  }

  Future<void> _send() async {
    final prompt = _input.text.trim();
    if (prompt.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _messages.add({'role': 'user', 'content': prompt});
      _pendingCode = null;
      _pendingPackage = null;
      _pendingSummary = null;
    });
    _input.clear();
    try {
      final reply = await PluginAiService.chat(
        messages: _conversation(),
        openBrowser: _openBrowser,
        listExtensions: _listExtensions,
        readExtension: _readExtension,
        proposeExtension: _proposeExtension,
      );
      if (mounted) {
        setState(() => _messages.add({'role': 'assistant', 'content': reply}));
      }
    } catch (error) {
      if (mounted) {
        setState(() =>
            _messages.add({'role': 'assistant', 'content': 'AI 请求失败：$error'}));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              _scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  Future<void> _applyProposal() async {
    final code = _pendingCode;
    final package = _pendingPackage;
    if (code == null || package == null) return;
    final existing = ExtensionUtils.runtimes[package];
    try {
      if (existing == null) {
        await ExtensionUtils.installByScript(code, context);
      } else {
        final file = File('${ExtensionUtils.extensionsDir}/$package.js');
        await file.writeAsString(code);
        await ExtensionUtils.installByPath(file.path);
      }
      if (!mounted) return;
      setState(() {
        _pendingCode = null;
        _pendingPackage = null;
        _pendingSummary = null;
      });
      showPlatformSnackbar(
          context: context, title: '插件代码已应用', content: package);
    } catch (error) {
      if (mounted) {
        showPlatformSnackbar(
            context: context, title: '应用插件失败', content: error.toString());
      }
    }
  }

  Widget _message(Map<String, dynamic> message) {
    final user = message['role'] == 'user';
    final content = message['content']?.toString() ?? '';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 840),
        margin: const EdgeInsets.symmetric(vertical: 7),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : fluent.FluentTheme.of(context).micaBackgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user ? '你' : 'AI',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SelectableText(content),
        ]),
      ),
    );
  }

  Widget _browserPanel() => SizedBox(
        height: 220,
        child: Column(children: [
          Row(children: [
            const Icon(Icons.public, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_browserUrl ?? '内置浏览器',
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
            IconButton(
                tooltip: '关闭浏览器',
                onPressed: () => setState(() => _showBrowser = false),
                icon: const Icon(Icons.close)),
          ]),
          Expanded(
            child: InAppWebView(
              keepAlive: _keepAlive,
              initialUrlRequest: _browserUrl == null
                  ? null
                  : URLRequest(url: WebUri(_browserUrl!)),
              onWebViewCreated: (controller) => _browserController = controller,
              onLoadStop: (controller, url) {
                if (url != null && mounted) {
                  setState(() => _browserUrl = url.toString());
                }
              },
            ),
          ),
        ]),
      );

  Widget _chatContent() {
    final selected = _selectedExtension;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        child: Row(children: [
          const Icon(Icons.auto_awesome_outlined),
          const SizedBox(width: 10),
          const Text('AI 对话',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(width: 20),
          SizedBox(
            width: 270,
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedPackage,
              decoration:
                  const InputDecoration(labelText: '操作插件', isDense: true),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('未指定，允许创建新插件')),
                for (final runtime in _extensions)
                  DropdownMenuItem<String?>(
                    value: runtime.extension.package,
                    child: Text(
                        '${runtime.extension.name} (${runtime.extension.package})',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _selectedPackage = value),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: _showBrowser ? '隐藏浏览器' : '显示浏览器',
            onPressed: () => setState(() => _showBrowser = !_showBrowser),
            icon: const Icon(Icons.public),
          ),
          IconButton(
            tooltip: '新建插件',
            onPressed: () => setState(() => _selectedPackage = null),
            icon: const Icon(Icons.add_box_outlined),
          ),
        ]),
      ),
      if (selected != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                '目标：${selected.extension.name} · ${selected.extension.package}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      if (_showBrowser) _browserPanel(),
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          itemCount: _messages.length,
          itemBuilder: (context, index) => _message(_messages[index]),
        ),
      ),
      if (_pendingCode != null)
        Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.primary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.code),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    '${_pendingSummary ?? '生成插件代码'} · ${_pendingPackage ?? ''}')),
            IconButton(
                tooltip: '查看生成代码',
                onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('待应用代码：$_pendingPackage'),
                        content: SizedBox(
                            width: 760,
                            child: SingleChildScrollView(
                                child: SelectableText(_pendingCode!))),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('关闭'))
                        ],
                      ),
                    ),
                icon: const Icon(Icons.visibility_outlined)),
            FilledButton.icon(
                onPressed: _applyProposal,
                icon: const Icon(Icons.check),
                label: const Text('应用')),
            IconButton(
                tooltip: '丢弃代码',
                onPressed: () => setState(() {
                      _pendingCode = null;
                      _pendingPackage = null;
                      _pendingSummary = null;
                    }),
                icon: const Icon(Icons.close)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: _selectedPackage == null
                    ? '描述要创建的插件或开发需求'
                    : '描述要修改 ${selected?.extension.name ?? '插件'} 的内容',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            tooltip: '发送',
            onPressed: _busy ? null : _send,
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
          ),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return Scaffold(body: SafeArea(child: _chatContent()));
    }
    return fluent.ScaffoldPage(content: _chatContent());
  }
}
