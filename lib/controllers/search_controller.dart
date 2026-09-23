import 'package:get/get.dart';
import 'package:miru_app/models/extension.dart';
import 'package:miru_app/utils/extension.dart';
import 'package:miru_app/data/services/extension_service.dart';
import 'package:miru_app/utils/miru_storage.dart';

class SearchPageController extends GetxController {
  Rx<ExtensionType?> cuurentExtensionType = Rx(null);
  final search = ''.obs;
  final searchResultList = <SearchResult>[].obs;
  String _randomKey = "";
  int get finishCount =>
      searchResultList.where((element) => element.completed).length;
  bool needRefresh = true;
  bool isPageOpen = false;
  bool _prioritizeResults = true;
  // 是否打开了这个页面

  @override
  void onInit() {
    ever(search, (callback) {
      _randomKey = DateTime.now().millisecondsSinceEpoch.toString();
      getResult(_randomKey, prioritizeResults: _prioritizeResults);
    });
    super.onInit();
  }

  getRuntime({ExtensionType? type, bool prioritizeResults = true}) {
    _randomKey = DateTime.now().millisecondsSinceEpoch.toString();
    _prioritizeResults = prioritizeResults;
    cuurentExtensionType.value = type;
    final exts = ExtensionUtils.runtimes.values.toList();
    if (type != null) {
      exts.removeWhere((element) => element.extension.type != type);
    }
    if (!MiruStorage.getSetting(SettingKey.enableNSFW)) {
      exts.removeWhere((element) => element.extension.nsfw);
    }
    searchResultList.clear();
    for (var element in exts) {
      searchResultList.add(SearchResult(runitme: element));
    }
    getResult(_randomKey, prioritizeResults: _prioritizeResults);
    needRefresh = false;
  }

  Future<void> getResult(String key, {required bool prioritizeResults}) async {
    final futures = <Future>[];
    // 最后一个有结果的搜索结果索引
    var lastResultIndex = -1;
    for (var i = 0; i < searchResultList.length; i++) {
      final element = searchResultList[i];
      element.completed = false;
      element.result = null;
      element.page = 1;
      element.filters = null;
      element.selectedFilters.clear();
      element.error = null;
      Future<List<ExtensionListItem>> resultFuture;

      if (search.value.isEmpty) {
        resultFuture = element.runitme.latest(1);
      } else {
        resultFuture = element.runitme.search(search.value, 1);
      }

      futures.add(
        resultFuture.then<void>((result) {
          if (_randomKey != key) return;
          element.result = result;
          if (prioritizeResults && result.isNotEmpty) {
            searchResultList.remove(element);
            if (lastResultIndex == -1) {
              searchResultList.insert(0, element);
              lastResultIndex = 0;
            } else {
              searchResultList.insert(lastResultIndex + 1, element);
              lastResultIndex++;
            }
          }
        }).catchError((Object error) {
          if (_randomKey == key) element.error = error.toString();
        }).whenComplete(() {
          if (_randomKey == key) {
            element.completed = true;
            searchResultList.refresh();
          }
        }),
      );
    }

    await Future.wait(futures);
  }

  Future<void> loadMore(SearchResult result) async {
    if (result.loadingMore || result.result == null) return;
    result.loadingMore = true;
    searchResultList.refresh();
    try {
      final nextPage = result.page + 1;
      final data = search.value.isEmpty
          ? result.selectedFilters.isEmpty
              ? await result.runitme.latest(nextPage)
              : await result.runitme.search(
                  '',
                  nextPage,
                  filter: result.selectedFilters,
                )
          : await result.runitme.search(
              search.value,
              nextPage,
              filter: result.selectedFilters.isEmpty
                  ? null
                  : result.selectedFilters,
            );
      result.result!.addAll(data);
      result.page = nextPage;
    } catch (error) {
      result.error = error.toString();
    } finally {
      result.loadingMore = false;
      searchResultList.refresh();
    }
  }

  Future<void> loadFilters(SearchResult result) async {
    result.filters = await result.runitme.createFilter(
      filter: result.selectedFilters.isEmpty ? null : result.selectedFilters,
    );
    for (final entry in result.filters!.entries) {
      result.selectedFilters.putIfAbsent(
        entry.key,
        () => entry.value.defaultOption.isEmpty
            ? <String>[]
            : [entry.value.defaultOption],
      );
    }
    searchResultList.refresh();
  }

  Future<void> applyFilters(
      SearchResult result, Map<String, List<String>> filters) async {
    result.selectedFilters = filters;
    result.page = 1;
    result.loadingMore = true;
    result.error = null;
    searchResultList.refresh();
    try {
      result.result = search.value.isEmpty && filters.isEmpty
          ? await result.runitme.latest(1)
          : await result.runitme.search(
              search.value,
              1,
              filter: filters.isEmpty ? null : filters,
            );
    } catch (error) {
      result.error = error.toString();
    } finally {
      result.loadingMore = false;
      searchResultList.refresh();
    }
  }

  getPackgeByIndex(int index) {
    return searchResultList[index].runitme.extension.package;
  }

  callRefresh() {
    if (isPageOpen) {
      getRuntime();
    } else {
      needRefresh = true;
    }
  }
}

class SearchResult {
  final ExtensionService runitme;
  List<ExtensionListItem>? result;
  String? error;
  bool completed;
  bool loadingMore = false;
  int page = 1;
  Map<String, ExtensionFilter>? filters;
  Map<String, List<String>> selectedFilters = {};
  SearchResult({
    required this.runitme,
    this.error,
    this.result,
    this.completed = false,
  });
}
