import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:miru_app/utils/miru_storage.dart';

class PluginAiService {
  static const _tools = [
    {
      'type': 'function',
      'function': {
        'name': 'browser_open',
        'description': '在 Miru 插件编辑页的内置浏览器中打开网页并读取可见文本。',
        'parameters': {
          'type': 'object',
          'properties': {
            'url': {'type': 'string', 'description': '要打开的 http 或 https 地址'},
          },
          'required': ['url'],
        },
      },
    },
  ];

  static Future<String> chat({
    required List<Map<String, dynamic>> messages,
    required Future<String> Function(String url) openBrowser,
  }) async {
    final baseUrl = (MiruStorage.getSetting(SettingKey.aiBaseUrl) as String)
        .trim()
        .replaceFirst(RegExp(r'/+$'), '');
    final apiKey =
        (MiruStorage.getSetting(SettingKey.aiApiKey) as String).trim();
    final model = (MiruStorage.getSetting(SettingKey.aiModel) as String).trim();
    if (apiKey.isEmpty) throw StateError('请先在设置中填写 AI API Key');
    if (model.isEmpty) throw StateError('请先在设置中选择 AI 模型');

    final dio = Dio();
    for (var step = 0; step < 5; step++) {
      final response = await dio.post<Map<String, dynamic>>(
        '$baseUrl/chat/completions',
        options: Options(headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        }),
        data: {
          'model': model,
          'messages': messages,
          'tools': _tools,
          'tool_choice': 'auto',
        },
      );
      final choice = (response.data!['choices'] as List).first as Map;
      final message = Map<String, dynamic>.from(choice['message'] as Map);
      final toolCalls = message['tool_calls'] as List? ?? const [];
      messages.add(message);
      if (toolCalls.isEmpty) return message['content']?.toString() ?? '';

      for (final rawCall in toolCalls) {
        final call = Map<String, dynamic>.from(rawCall as Map);
        final function = Map<String, dynamic>.from(call['function'] as Map);
        final arguments = Map<String, dynamic>.from(
          _decodeArguments(function['arguments']?.toString() ?? '{}'),
        );
        String result;
        if (function['name'] == 'browser_open') {
          final uri = Uri.tryParse(arguments['url']?.toString() ?? '');
          if (uri == null || !{'http', 'https'}.contains(uri.scheme)) {
            result = '只允许打开 http 或 https 网页';
          } else {
            result = await openBrowser(uri.toString());
          }
        } else {
          result = '不支持的工具：${function['name']}';
        }
        messages.add({
          'role': 'tool',
          'tool_call_id': call['id'],
          'content': result,
        });
      }
    }
    throw StateError('AI 工具调用轮数超限');
  }

  static Map<String, dynamic> _decodeArguments(String value) =>
      Map<String, dynamic>.from(jsonDecode(value) as Map);
}
