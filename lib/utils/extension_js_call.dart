import 'dart:convert';

String extensionJsCall(
  String className,
  String method,
  List<Object?> arguments,
) {
  final encodedArguments = jsonEncode(jsonEncode(arguments));
  return '${className}Instance.$method(...JSON.parse($encodedArguments))';
}

String extensionJsPromiseCall(
  String className,
  String method,
  List<Object?> arguments,
) {
  return 'stringify(() => ${extensionJsCall(className, method, arguments)})';
}
