import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:get/get.dart';
import 'package:miru_app/models/index.dart';
import 'package:miru_app/utils/miru_storage.dart';
import 'package:miru_app/utils/request.dart';

class ExtensionRepoPageController extends GetxController {
  List<dynamic> extensions = <dynamic>[].obs;
  List<dynamic> extensionsTemp = <dynamic>[];

  final isLoading = false.obs;
  final isError = false.obs;
  final search = ''.obs;
  final Rx<ExtensionType?> searchType = Rx(null);

  @override
  void onInit() {
    onRefresh();
    super.onInit();
  }

  /// 获取当前配置的仓库 URL
  String get repoUrl => MiruStorage.getSetting(SettingKey.extensionRepoUrl) ?? '';

  /// 检查是否已配置仓库
  bool get hasRepoConfigured => repoUrl.isNotEmpty;

  onRefresh() async {
    isLoading.value = true;
    isError.value = false;

    // 如果没有配置仓库 URL，显示空列表
    if (!hasRepoConfigured) {
      extensions = [];
      extensionsTemp = [];
      isLoading.value = false;
      return;
    }

    // 优先使用本地缓存的索引
    final cachedIndex = MiruStorage.getSetting(SettingKey.extensionRepoIndex);
    if (cachedIndex != null && cachedIndex.isNotEmpty) {
      try {
        extensions = jsonDecode(cachedIndex);
        _filterNsfw();
        extensionsTemp.clear();
        extensionsTemp.addAll(extensions);
      } catch (_) {
        // 缓存解析失败，尝试从网络加载
      }
    }

    // 从网络刷新
    try {
      final baseUrl = repoUrl.endsWith('/') ? repoUrl.substring(0, repoUrl.length - 1) : repoUrl;
      final res = await dio.get<String>('$baseUrl/index.json');
      extensions = jsonDecode(res.data!);

      // 缓存索引
      MiruStorage.setSetting(SettingKey.extensionRepoIndex, res.data!);

      _filterNsfw();
      extensionsTemp.clear();
      extensionsTemp.addAll(extensions);
    } catch (e) {
      // 如果没有缓存且网络失败，标记错误
      if (extensions.isEmpty) {
        isError.value = true;
      }
      debugPrint(e.toString());
    } finally {
      isLoading.value = false;
    }
  }

  void _filterNsfw() {
    if (!MiruStorage.getSetting(SettingKey.enableNSFW)) {
      extensions.removeWhere((element) => element['nsfw'] == "true");
    }
  }

  /// 设置仓库 URL
  Future<void> setRepoUrl(String url) async {
    await MiruStorage.setSetting(SettingKey.extensionRepoUrl, url);
    await MiruStorage.setSetting(SettingKey.extensionRepoIndex, '[]');
    onRefresh();
  }

  /// 清除仓库配置
  Future<void> clearRepo() async {
    await MiruStorage.setSetting(SettingKey.extensionRepoUrl, '');
    await MiruStorage.setSetting(SettingKey.extensionRepoIndex, '[]');
    extensions = [];
    extensionsTemp = [];
    update();
  }
}
