import 'package:get/get.dart';
import 'package:miru_app/data/services/extension_service.dart';
import 'package:miru_app/models/extension.dart';
import 'package:miru_app/utils/extension.dart';

class ExtensionPageController extends GetxController {
  RxMap<String, ExtensionService> runtimes = <String, ExtensionService>{}.obs;
  RxMap<String, String> errors = <String, String>{}.obs;
  RxBool isInstallloading = false.obs;
  bool needRefresh = true;
  bool isPageOpen = false;
  
  // 筛选类型
  final Rx<ExtensionType?> searchType = Rx(null);

  @override
  void onInit() {
    onRefresh();
    super.onInit();
  }

  onRefresh() async {
    runtimes.clear();
    errors.clear();
    runtimes.addAll(ExtensionUtils.runtimes);
    errors.addAll(ExtensionUtils.extensionErrorMap);
  }

  callRefresh() {
    if (isPageOpen) {
      onRefresh();
    } else {
      needRefresh = true;
    }
  }
}
