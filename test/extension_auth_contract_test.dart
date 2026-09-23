import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('repo/js/cycani.js').readAsStringSync();

  test('Cycani uses the native form login and stores its auth token', () {
    expect(source, contains("return { mode: 'form' }"));
    expect(source, contains("this.request('/auth/login'"));
    expect(source, contains("this.setSetting('authToken', payload.token)"));
  });

  test('Cycani playback requires and sends the saved bearer token', () {
    expect(source, contains("this.getSetting('authToken')"));
    expect(source, contains(r'Authorization: `Bearer ${token}`'));
    expect(source, contains('登录已失效，请重新登录次元城动画。'));
  });
}
