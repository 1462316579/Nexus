import 'package:flutter/material.dart';
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
  late final Future<String> loginUrl = _getLoginUrl();
  late final Future<List<Map<String, dynamic>>> form =
      widget.runtime.loginForm();
  final Map<String, TextEditingController> _values = {};
  bool _busy = false;
  String? _message;

  Future<String> _getLoginUrl() async =>
      await widget.runtime.login() ?? widget.runtime.extension.webSite;

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
      final result =
          await widget.runtime.sendLoginVerificationCode(key, _formValues);
      if (mounted) setState(() => _message = result);
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
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final success = await widget.runtime.submitLogin(_formValues);
      if (success) {
        await widget.runtime.setCookie(await widget.runtime.listCookie());
        if (mounted) setState(() => _message = '登录成功');
      } else if (mounted) {
        setState(() => _message = '登录失败，请检查输入内容');
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _loginForm(List<Map<String, dynamic>> fields) {
    if (fields.isEmpty) {
      return FutureBuilder<String>(
        future: loginUrl,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: SelectableText(snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return WebViewPage(
            key: ValueKey(snapshot.data),
            extensionRuntime: widget.runtime,
            url: snapshot.data!,
          );
        },
      );
    }

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
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              for (final field in fields)
                if (field['key'] is String &&
                    _values.containsKey(field['key'])) ...[
                  if (field['type'] == 'captcha' && field['imageUrl'] is String)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Image.network(field['imageUrl'] as String),
                    ),
                  TextField(
                    controller: _values[field['key'] as String],
                    obscureText: field['type'] == 'password',
                    keyboardType: field['type'] == 'email'
                        ? TextInputType.emailAddress
                        : field['type'] == 'phone'
                            ? TextInputType.phone
                            : TextInputType.text,
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
    );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: form,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
                body: Center(child: SelectableText(snapshot.error.toString())));
          }
          if (!snapshot.hasData) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return _loginForm(snapshot.data!);
        },
      );
}
