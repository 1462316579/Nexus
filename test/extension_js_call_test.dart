import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miru_app/utils/extension_js_call.dart';

void main() {
  test('search arguments preserve quotes, slashes and control characters', () {
    const keyword = 'quote " slash \\ newline\n tab\t snowman ☃';
    const filters = {
      'category': ['A"B', r'C\D'],
    };
    final source = extensionJsCall(
      'testExtension',
      'search',
      [keyword, 2, filters],
    );
    final encoded =
        RegExp(r'JSON\.parse\((".*")\)').firstMatch(source)!.group(1)!;
    final arguments = jsonDecode(jsonDecode(encoded) as String) as List;

    expect(arguments[0], keyword);
    expect(arguments[1], 2);
    expect(arguments[2], filters);
  });

  test('promise invocation uses the same encoded method arguments', () {
    const keyword = '"quoted" \\ path\nnext line';
    final source = extensionJsPromiseCall(
      'testExtension',
      'search',
      [keyword, 1, null],
    );

    expect(source, contains('stringify(() =>'));
    expect(source, contains('testExtensionInstance.search(...JSON.parse('));
    expect(source, contains(jsonEncode(jsonEncode([keyword, 1, null]))));
  });

  test('missing search filters can be normalized before JS invocation', () {
    const keyword = 'query';
    const Map<String, List<String>>? filters = null;
    final normalizedFilters = filters ?? <String, List<String>>{};
    final source = extensionJsCall(
      'testExtension',
      'search',
      [keyword, 1, normalizedFilters],
    );
    final encoded =
        RegExp(r'JSON\.parse\((".*")\)').firstMatch(source)!.group(1)!;
    final arguments = jsonDecode(jsonDecode(encoded) as String) as List;

    expect(arguments[2], isEmpty);
  });
}
