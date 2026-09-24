import 'dart:convert';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:miru_app/models/extension.dart';
import 'package:miru_app/controllers/extension/extension_controller.dart';
import 'package:miru_app/controllers/search_controller.dart';
import 'package:miru_app/data/services/extension_service.dart';
import 'package:miru_app/utils/i18n.dart';
import 'package:miru_app/utils/miru_directory.dart';
import 'package:miru_app/utils/request.dart';
import 'package:miru_app/utils/router.dart';
import 'package:miru_app/views/widgets/button.dart';
import 'package:miru_app/views/widgets/messenger.dart';
import 'package:path/path.dart' as path;

class ExtensionUtils {
  static Map<String, ExtensionService> runtimes = {};
  static Map<String, String> extensionErrorMap = {};
  static final Map<String, List<ExtensionLog>> logs = {};
  static final Map<String, Map<String, ExtensionNetworkLog>> networkLogs = {};

  // 首次扩展扫描是否已完成（ensureInitialized 中逐个初始化运行时可能慢于首帧）
  static bool isLoaded = false;
  // 扩展列表发生变化（首次加载完成、目录文件增删改）时的监听者
  static final List<void Function()> _updateListeners = [];

  static void addExtensionUpdateListener(void Function() listener) {
    if (!_updateListeners.contains(listener)) {
      _updateListeners.add(listener);
    }
  }

  static void removeExtensionUpdateListener(void Function() listener) {
    _updateListeners.remove(listener);
  }

  static void _notifyUpdateListeners() {
    for (final listener in List<void Function()>.from(_updateListeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  static String get extensionsDir => path.join(
        MiruDirectory.getDirectory,
        'extensions',
      );

  // 初始化扩展
  static ensureInitialized() async {
    // 创建目录
    Directory(extensionsDir).createSync(recursive: true);
    await _loadExtensions();
    // 监听目录变化
    Directory(extensionsDir).watch().listen((event) async {
      if (path.extension(event.path) == '.js') {
        final package = path.basenameWithoutExtension(event.path);
        debugPrint('extension event: ${event.path} ${event.type}');
        runtimes.remove(package);
        extensionErrorMap.remove(event.path);
        switch (event.type) {
          case FileSystemEvent.delete:
            break;
          case FileSystemEvent.create:
          case FileSystemEvent.modify:
            await installByPath(event.path);
            break;
        }
        _reloadPage();
        _notifyUpdateListeners();
      }
    });
  }

  static _loadExtensions() async {
    // 获取扩展列表
    final extensionsList = Directory(extensionsDir).listSync();
    // 遍历扩展列表
    for (final extension in extensionsList) {
      await installByPath(extension.path);
    }

    isLoaded = true;
    _reloadPage();
    // 通知通过 tag 注册、_reloadPage 无法找到的页面控制器（如首页内容页）
    _notifyUpdateListeners();
  }

  static uninstall(String package) async {
    final file = File(path.join(extensionsDir, '$package.js'));
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  static install(String url, BuildContext context) async {
    try {
      final res = await dio.get<String>(url);
      if (res.data == null) {
        throw Exception("Does not seem to be an extension");
      }
      final ext = ExtensionUtils.parseExtension(res.data!);
      final savePath = path.join(extensionsDir, '${ext.package}.js');
      // 保存文件
      File(savePath).writeAsStringSync(res.data!);
      //reload
      _loadExtensions();
    } catch (e) {
      if (context.mounted) {
        showPlatformDialog(
          context: context,
          title: 'extension-install-error'.i18n,
          content: Text(e.toString()),
          actions: [
            PlatformButton(
              child: Text('common.close'.i18n),
              onPressed: () {
                RouterUtils.pop();
              },
            )
          ],
        );
      }
      rethrow;
    }
  }

  static installByScript(String script, BuildContext context) async {
    try {
      final ext = ExtensionUtils.parseExtension(script);
      final savePath = path.join(extensionsDir, '${ext.package}.js');
      // 保存文件
      File(savePath).writeAsStringSync(script);
      runtimes[ext.package] = await ExtensionService().initRuntime(ext);
      _reloadPage();
    } catch (e) {
      if (context.mounted) {
        showPlatformDialog(
          context: context,
          title: 'extension-install-error'.i18n,
          content: Text(e.toString()),
          actions: [
            PlatformButton(
              child: Text('common.close'.i18n),
              onPressed: () {
                RouterUtils.pop();
              },
            )
          ],
        );
      }
      rethrow;
    }
  }

  /// 从 JSON 聚合文件批量安装插件
  ///
  /// JSON 格式为插件数组，每个插件包含 name、package、type、url 等字段。
  /// url 字段为相对于 JSON 文件的路径。
  static Future<int> installByJson(
    String jsonPath,
    BuildContext context,
  ) async {
    try {
      final jsonFile = File(jsonPath);
      final jsonDir = path.dirname(jsonPath);
      final jsonContent =
          (await jsonFile.readAsString()).replaceFirst('\uFEFF', '');

      dynamic parsed;
      try {
        parsed = jsonDecode(jsonContent);
      } catch (e) {
        throw FormatException('Invalid JSON format: $e');
      }

      final items = parsed is List
          ? parsed
          : parsed is Map && parsed['extensions'] is List
              ? parsed['extensions'] as List
              : null;
      if (items == null) {
        throw const FormatException(
          'JSON must be an array or an object containing an extensions array',
        );
      }

      int installed = 0;
      for (final item in items) {
        if (item is! Map) continue;

        final url = item['url'] as String?;
        if (url == null || url.isEmpty) continue;

        // 同时兼容两种 JSON 路径格式：
        // 1. 相对于 JSON 文件：js/video/cycani.js
        // 2. 相对于项目根目录：repo/js/video/cycani.js
        final candidates = <String>[
          path.isAbsolute(url) ? url : path.join(jsonDir, url),
          if (!path.isAbsolute(url)) path.join(Directory.current.path, url),
          if (!path.isAbsolute(url)) path.join(path.dirname(jsonDir), url),
        ];
        final jsPath = candidates.firstWhere(
          (candidate) => File(candidate).existsSync(),
          orElse: () => '',
        );

        if (jsPath.isEmpty) {
          debugPrint('Plugin file not found. Tried: ${candidates.join(', ')}');
          continue;
        }

        try {
          final script = await File(jsPath).readAsString();
          final ext = ExtensionUtils.parseExtension(script);

          // JSON 索引中的文件名可以与 package 不同，例如 cycani.js 对应 org.cycani。
          // package 是插件的唯一标识，保存时统一使用解析出的 package。

          // 保存文件
          final savePath = path.join(extensionsDir, '${ext.package}.js');
          File(savePath).writeAsStringSync(script);

          // 初始化运行时
          if (!runtimes.containsKey(ext.package)) {
            runtimes[ext.package] = await ExtensionService().initRuntime(ext);
          }

          installed++;
          debugPrint('Installed plugin: ${ext.package} from $jsPath');
        } catch (e) {
          debugPrint('Failed to install plugin from $jsPath: $e');
        }
      }

      if (installed > 0) {
        _reloadPage();
      }

      return installed;
    } catch (e) {
      if (context.mounted) {
        showPlatformDialog(
          context: context,
          title: 'extension-install-error'.i18n,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Failed to import plugins from JSON'),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            PlatformButton(
              child: Text('common.close'.i18n),
              onPressed: () {
                RouterUtils.pop();
              },
            )
          ],
        );
      }
      rethrow;
    }
  }

  /// 从目录批量安装插件（递归扫描 .js 文件）
  static Future<int> installByDirectory(
    String dirPath,
    BuildContext context,
  ) async {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        throw Exception('Directory does not exist: $dirPath');
      }

      int installed = 0;

      // 递归查找所有 .js 文件
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && path.extension(entity.path) == '.js') {
          try {
            final jsPath = entity.path;
            final script = await File(jsPath).readAsString();
            final ext = ExtensionUtils.parseExtension(script);

            // 检查文件名与包名是否一致
            final jsFileName = path.basenameWithoutExtension(jsPath);
            if (jsFileName != ext.package) {
              debugPrint(
                'File name mismatch: expected ${ext.package}, got $jsFileName',
              );
              continue;
            }

            // 保存文件
            final savePath = path.join(extensionsDir, '${ext.package}.js');
            File(savePath).writeAsStringSync(script);

            // 初始化运行时
            if (!runtimes.containsKey(ext.package)) {
              runtimes[ext.package] = await ExtensionService().initRuntime(ext);
            }

            installed++;
            debugPrint('Installed plugin: ${ext.package} from $jsPath');
          } catch (e) {
            debugPrint('Failed to install plugin from ${entity.path}: $e');
          }
        }
      }

      if (installed > 0) {
        _reloadPage();
      }

      return installed;
    } catch (e) {
      if (context.mounted) {
        showPlatformDialog(
          context: context,
          title: 'extension-install-error'.i18n,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Failed to import plugins from directory'),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            PlatformButton(
              child: Text('common.close'.i18n),
              onPressed: () {
                RouterUtils.pop();
              },
            )
          ],
        );
      }
      rethrow;
    }
  }

  static installByPath(String p) async {
    if (path.extension(p) == '.js') {
      try {
        final file = File(p);
        final content = await file.readAsString();
        // 如果文件名和包名不一致，抛出异常
        final ext = ExtensionUtils.parseExtension(content);
        if (path.basenameWithoutExtension(p) != ext.package) {
          throw Exception("Inconsistency between file name and package name");
        }
        runtimes[ext.package] = await ExtensionService().initRuntime(ext);
      } catch (e) {
        extensionErrorMap[p] = e.toString();
      }
    }
  }

  static _reloadPage() {
    // 重载扩展页面
    if (Get.isRegistered<ExtensionPageController>()) {
      Get.find<ExtensionPageController>().callRefresh();
    }
    // 重载搜索页面
    if (Get.isRegistered<SearchPageController>()) {
      Get.find<SearchPageController>().callRefresh();
    }
  }

  static String typeToString(ExtensionType type) {
    switch (type) {
      case ExtensionType.bangumi:
        return 'extension-type.video'.i18n;
      case ExtensionType.fikushon:
        return 'extension-type.novel'.i18n;
      case ExtensionType.manga:
        return 'extension-type.comic'.i18n;
      case ExtensionType.music:
        return '音乐';
    }
  }

  static void addLog(
    Extension ext,
    ExtensionLogLevel level,
    String logContent,
  ) {
    final entries = logs.putIfAbsent(ext.package, () => <ExtensionLog>[]);
    entries.add(ExtensionLog(
      extension: ext,
      content: logContent,
      time: DateTime.now(),
      level: level,
    ));
    if (entries.length > 500) entries.removeAt(0);
  }

  static void addNetworkLog(String key, ExtensionNetworkLog log) {
    final entries = networkLogs.putIfAbsent(
      log.extension.package,
      () => <String, ExtensionNetworkLog>{},
    );
    entries[key] = log;
    if (entries.length > 500) entries.remove(entries.keys.first);
  }

  static Future<String> callPluginMethod(
    String script,
    String method,
    BuildContext context,
  ) async {
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(method)) {
      throw const FormatException('Invalid plugin method name');
    }
    final extension = parseExtension(script);
    await installByScript(script, context);
    return runtimes[extension.package]!.debugExecute(method);
  }

  static void clearDebugLogs(String package) {
    logs.remove(package);
    networkLogs.remove(package);
  }

  // ==MiruExtension==
  // @name         Enime
  // @version      v0.0.1
  // @author       MiaoMint
  // @lang         all
  // @license      MIT
  // @icon         https://avatars.githubusercontent.com/u/74993083?s=200&v=4
  // @package      moe.enime
  // @type         bangumi
  // @webSite      https://api.enime.moe/
  // @description  Enime API is an open source API service for developers to access anime info (as well as their video sources) https://github.com/Enime-Project/api.enime.moe
  // ==/MiruExtension==

  // 解析扩展为元数据
  static Extension parseExtension(String extension) {
    Map<String, dynamic> result = {};
    RegExp exp = RegExp(r'@(\w+)\s+(.*)');
    Iterable<RegExpMatch> matches = exp.allMatches(extension);
    for (RegExpMatch match in matches) {
      result[match.group(1)!] = match.group(2);
    }
    result['nsfw'] = result['nsfw'] == "true";
    final type = (result['type'] as String? ?? '').trim().toLowerCase();
    if (!const {'manga', 'bangumi', 'fikushon', 'music'}.contains(type)) {
      throw FormatException('Unsupported extension type: $type');
    }
    result['type'] = type;
    return Extension.fromJson(result);
  }
}
