import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:miru_app/data/services/extension_service.dart';
import 'package:miru_app/models/extension.dart';
import 'package:miru_app/utils/extension.dart';
import 'package:miru_app/views/pages/webview_page.dart';

class ExtensionLoginPage extends StatefulWidget {
  const ExtensionLoginPage({super.key, required this.runtime});

  final ExtensionService runtime;

  @override
  State<ExtensionLoginPage> createState() => _ExtensionLoginPageState();
}

class _ExtensionLoginPageState extends State<ExtensionLoginPage> {
  late final Future<Map<String, dynamic>> _config =
      widget.runtime.loginConfig();
  late final Future<List<Map<String, dynamic>>> _form =
      widget.runtime.loginForm();
  final Map<String, TextEditingController> _values = {};
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    for (final controller in _values.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _formValues => {
        for (final entry in _values.entries) entry.key: entry.value.text,
      };

  Future<void> _requestCode(String key) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await widget.runtime.sendLoginVerificationCode(
        key,
        _formValues,
      );
      if (mounted) setState(() => _message = message);
    } catch (error) {
      ExtensionUtils.addLog(
        widget.runtime.extension,
        ExtensionLogLevel.error,
        error.toString(),
      );
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final success = await widget.runtime.submitLogin(_formValues);
      if (success) {
        await widget.runtime.setCookie(await widget.runtime.listCookie());
        if (mounted) {
          if (Platform.isAndroid) {
            Get.back();
          } else {
            context.go('/settings');
          }
        }
      } else if (mounted) {
        setState(() => _message = '登录失败，请检查输入内容');
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _formPage(List<Map<String, dynamic>> fields) {
    for (final field in fields) {
      final key = field['key'];
      if (key is String) {
        _values.putIfAbsent(key, () => TextEditingController());
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text('${widget.runtime.extension.name} 登录')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                for (final field in fields)
                  if (field['key'] is String &&
                      _values.containsKey(field['key'])) ...[
                    if (field['type'] == 'captcha' &&
                        field['imageUrl'] is String)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Image.network(field['imageUrl'] as String),
                      ),
                    TextFormField(
                      controller: _values[field['key'] as String],
                      obscureText: field['type'] == 'password',
                      keyboardType: field['type'] == 'email'
                          ? TextInputType.emailAddress
                          : field['type'] == 'phone'
                              ? TextInputType.phone
                              : TextInputType.text,
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return '请输入${field['label'] as String? ?? field['key'] as String}';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText:
                            field['label'] as String? ?? field['key'] as String,
                        hintText: field['placeholder'] as String?,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (field['verification'] == true) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => _requestCode(field['key'] as String),
                          child: const Text('获取验证码'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(_message!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _config,
        builder: (context, configSnapshot) {
          if (configSnapshot.hasError) {
            return _errorPage(configSnapshot.error!);
          }
          if (!configSnapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final config = configSnapshot.data!;
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _form,
            builder: (context, formSnapshot) {
              if (formSnapshot.hasError) {
                return _errorPage(formSnapshot.error!);
              }
              if (!formSnapshot.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final fields = formSnapshot.data!;
              if (config['mode'] == 'form' || fields.isNotEmpty) {
                return _formPage(fields);
              }
              if (widget.runtime.extension.package == 'org.cycani') {
                return _errorPage('当前插件未提供登录输入框配置。');
              }
              return WebViewPage(
                key: ValueKey(config['url']),
                extensionRuntime: widget.runtime,
                url: config['url'] as String,
              );
            },
          );
        },
      );

  Widget _errorPage(Object error) => Scaffold(
        appBar: AppBar(title: Text('${widget.runtime.extension.name} 登录')),
        body: Center(child: SelectableText(error.toString())),
      );
}
