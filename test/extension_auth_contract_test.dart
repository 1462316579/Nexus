import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('repo/js/cycani.js').readAsStringSync();
  final repository = jsonDecode(File('repo/index.json').readAsStringSync());

  test('Extension repository has no built-in plugin sources', () {
    expect(repository, isEmpty);
  });

  test('Cycani uses the native form login and stores its auth token', () {
    expect(source, contains("return { mode: 'form' }"));
    expect(source, contains("this.request('/api/auth/login'"));
    expect(source, contains("this.setSetting('authToken', payload.token)"));
    expect(source, contains("'authUser',"));
    expect(source, contains("'authExpiresAt',"));
  });

  test('Cycani playback requires and sends the saved bearer token', () {
    expect(source, contains("this.getSetting('authToken')"));
    expect(source, contains(r'Authorization: `Bearer ${token}`'));
    // 过期 token 自动清除后抛出明确指引
    expect(source, contains('登录已过期，请前往设置重新登录次元城动画。'));
    // 401 HTTP 异常时也清除 token
    expect(source, contains('msg.includes(\'401\') || msg.toLowerCase().includes(\'unauthorized\')'));
    expect(source, contains('登录已失效或被服务器吊销，请前往设置重新登录次元城动画。'));
    // watch 鉴权失败 → _clearAuth + 带服务端返回 msg 的错误
    expect(source, contains('data?.msg'));
    expect(source, contains('this._clearAuth()'));
  });

  test('Cycani reports login state through the getLoginStatus contract', () {
    expect(source, contains('async getLoginStatus()'));
    expect(source, contains('loggedIn: false'));
    expect(source, contains('loggedIn: true'));
    expect(source, contains("this.getSetting('authExpiresAt')"));
    expect(source, contains("this.getSetting('authUser')"));
  });

  test('Cycani validates token server-side (three-state) before trusting local cache', () {
    expect(source, contains('async _validateToken(token)'));
    expect(source, contains('/api/user/me'));
    // 三态返回：'valid' / 'invalid' / 'unknown'
    expect(source, contains("return 'valid'"));
    expect(source, contains("return 'invalid'"));
    expect(source, contains("return 'unknown'"));
    // 只有明确 invalid 才清除，unknown（网络错误等）保守保留 token
    expect(source, contains("if (validation === 'invalid')"));
    expect(source, contains('validation === \'unknown\''));
    expect(source, contains('保守信任本地状态'));
    expect(source, contains('async _clearAuth()'));
  });
}
