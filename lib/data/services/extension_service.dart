import 'dart:async';
import 'dart:convert';
import 'package:charset_converter/charset_converter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/extensions/fetch.dart';
import 'package:get/get.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:miru_app/data/services/extension_jscore_plugin.dart';
import 'package:miru_app/utils/log.dart';
import 'package:miru_app/utils/miru_storage.dart';
import 'package:miru_app/utils/request.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:miru_app/models/index.dart';
import 'package:miru_app/data/services/database_service.dart';
import 'package:miru_app/utils/extension.dart';
import 'package:miru_app/utils/extension_js_call.dart';
import 'package:flutter_js/javascriptcore/jscore_runtime.dart';

class ExtensionService extends ChangeNotifier {
  late JavascriptRuntime runtime;
  bool supportsLogin = false;
  bool isLoggedIn = false;
  String? loginUserLabel;
  late Extension extension;
  String _cuurentRequestUrl = '';
  String evalString = '';
  late JsBridge jsBridge;
  static Map<dynamic, dynamic> evalMap = {};
  String className = '';
  bool isinit = false;
  initRuntime(Extension ext) async {
    extension = ext;
    className = extension.package.replaceAll('.', '');
    // example: if the package name is com.example.extension the class name will be comexampleextension
    // but if  the package name is 9anime.to the class name will be animetoRenamed

    if (!className.isAlphabetOnly) {
      className = "${className.replaceAll(RegExp(r'[^a-zA-z]'), '')}Renamed";
    }
    // 读取文件
    final file =
        File('${ExtensionUtils.extensionsDir}/${extension.package}.js');
    final content = file.readAsStringSync();

    // 初始化runtime
    if (Platform.isAndroid) {
      runtime = QuickJsRuntime2(stackSize: 1024 * 1024);
    } else if (Platform.isWindows || Platform.isLinux) {
      runtime = QuickJsRuntime2();
    } else {
      runtime = JavascriptCoreRuntime();
    }
    runtime.enableFetch();
    runtime.enableHandlePromises();

    jsLog(dynamic args) {
      logger.info(args[0]);
      ExtensionUtils.addLog(
        extension,
        ExtensionLogLevel.info,
        args[0],
      );
    }

    Future<String> decodeTextResponse(
      List<int> bytes,
      Headers responseHeaders,
    ) async {
      final raw = Uint8List.fromList(bytes);
      final contentType = responseHeaders.value('content-type') ?? '';
      final headerCharset = RegExp(
        r"""charset\s*=\s*["']?([\w-]+)""",
        caseSensitive: false,
      ).firstMatch(contentType)?.group(1);
      final probe = latin1.decode(raw.take(8192).toList(), allowInvalid: true);
      final metaCharset = RegExp(
        r"""<meta[^>]+charset\s*=\s*["']?\s*([\w-]+)|"""
        r"""<meta[^>]+content\s*=\s*["'][^"']*charset\s*=\s*([\w-]+)""",
        caseSensitive: false,
      ).firstMatch(probe);
      final declared =
          (headerCharset ?? metaCharset?.group(1) ?? metaCharset?.group(2))
              ?.toLowerCase();
      final encoding = declared == 'gb2312' ||
              declared == 'gbk' ||
              declared == 'x-gbk' ||
              declared == 'gb18030'
          ? 'gb2312'
          : declared == 'big5'
              ? 'big5'
              : null;
      if (encoding == null) {
        try {
          return utf8.decode(raw, allowMalformed: false);
        } on FormatException {
          return CharsetConverter.decode('gb2312', raw);
        }
      }
      return CharsetConverter.decode(encoding, raw);
    }

    jsRequest(dynamic args) async {
      _cuurentRequestUrl = args[0];
      final url = args[0].toString();
      final headers = Map<String, dynamic>.from(args[1]['headers'] ?? {});
      if (headers['User-Agent'] == null) {
        headers['User-Agent'] = MiruStorage.getUASetting();
      }
      // 显式注入持久化 Cookie；Dio CookieManager 仍继续负责自动管理，
      // 这样桥接层和播放链路都能稳定获得登录会话。
      if (headers['Cookie'] == null) {
        final cookie = await MiruRequest.getCookie(url);
        if (cookie.isNotEmpty) headers['Cookie'] = cookie;
      }

      final method = args[1]['method'] ?? 'get';
      final isBinary = args[1]['binary'] == true;
      Object? requestBody = args[1]['data'];
      // 二进制请求（如 protobuf）：JS 侧以字节数组传入，转回 Uint8List 发送
      if (isBinary && requestBody is List) {
        requestBody = Uint8List.fromList(
          requestBody.map((e) => (e as num).toInt()).toList(),
        );
      }

      final log = ExtensionNetworkLog(
        extension: extension,
        url: args[0],
        method: method,
        requestHeaders: headers,
      );
      final key = UniqueKey().toString();
      ExtensionUtils.addNetworkLog(
        key,
        log,
      );

      try {
        if (isBinary) {
          // 二进制通道：请求体与响应体均为原始字节，响应以 JSON 字节数组回传 JS
          final res = await dio.request<List<int>>(
            url,
            data: requestBody,
            queryParameters: args[1]['queryParameters'] ?? {},
            options: Options(
              headers: headers,
              method: method,
              responseType: ResponseType.bytes,
            ),
          );
          final bytes = res.data ?? Uint8List(0);
          log.requestHeaders = res.requestOptions.headers;
          log.responseBody = '<binary ${bytes.length} bytes>';
          log.responseHeaders = res.headers.map.map(
            (key, value) => MapEntry(key, value.join(';')),
          );
          log.statusCode = res.statusCode;

          ExtensionUtils.addNetworkLog(key, log);
          return jsonEncode(bytes);
        }
        final res = await dio.request<List<int>>(
          url,
          data: requestBody,
          queryParameters: args[1]['queryParameters'] ?? {},
          options: Options(
            headers: headers,
            method: method,
            responseType: ResponseType.bytes,
          ),
        );
        final responseBytes = res.data ?? const <int>[];
        final responseHeaders = res.headers;
        final responseText =
            await decodeTextResponse(responseBytes, responseHeaders);
        log.requestHeaders = res.requestOptions.headers;
        log.responseBody = responseText;
        log.responseHeaders = responseHeaders.map.map(
          (key, value) => MapEntry(
            key,
            value.join(';'),
          ),
        );
        log.statusCode = res.statusCode;

        ExtensionUtils.addNetworkLog(key, log);
        return responseText;
      } on DioException catch (e) {
        log.url = e.requestOptions.uri.toString();
        log.requestHeaders = e.requestOptions.headers;
        final errorHeaders = e.response?.headers;
        final errorBytes = e.response?.data is List<int>
            ? List<int>.from(e.response!.data as List<int>)
            : null;
        final errorText =
            !isBinary && errorBytes != null && errorHeaders != null
                ? await decodeTextResponse(errorBytes, errorHeaders)
                : null;
        log.responseBody = isBinary && errorBytes != null
            ? '<binary ${errorBytes.length} bytes>'
            : errorText ?? e.response?.data?.toString();
        log.responseHeaders = errorHeaders?.map.map(
          (key, value) => MapEntry(key, value.join(';')),
        );
        log.statusCode = e.response?.statusCode;
        ExtensionUtils.addNetworkLog(key, log);
        if (e.response != null) {
          if (isBinary && errorBytes != null) return jsonEncode(errorBytes);
          return errorText ?? e.response?.data?.toString();
        }
        rethrow;
      }
    }

    jsRegisterSetting(dynamic args) async {
      args[0]['package'] = extension.package;

      return DatabaseService.registerExtensionSetting(
        ExtensionSetting()
          ..package = extension.package
          ..title = args[0]['title']
          ..key = args[0]['key']
          ..value = args[0]['value']
          ..type = ExtensionSetting.stringToType(args[0]['type'])
          ..description = args[0]['description']
          ..defaultValue = args[0]['defaultValue']
          ..options = jsonEncode(args[0]['options']),
      );
    }

    jsGetMessage(dynamic args) async {
      final setting =
          await DatabaseService.getExtensionSetting(extension.package, args[0]);
      return setting?.value ?? setting?.defaultValue;
    }

    jsSetSetting(dynamic args) async {
      await DatabaseService.setExtensionSettingValue(
        extension.package,
        args[0].toString(),
        args[1].toString(),
      );
      return true;
    }

    jsCleanSettings(dynamic args) async {
      // debugPrint('cleanSettings: ${args[0]}');
      return DatabaseService.cleanExtensionSettings(
          extension.package, List<String>.from(args[0]));
    }

    jsQuerySelector(dynamic args) {
      final content = args[0];
      final selector = args[1];
      final fun = args[2];

      final doc = parse(content).querySelector(selector);
      String result = '';
      switch (fun) {
        case 'text':
          result = doc?.text ?? '';
        case 'outerHTML':
          result = doc?.outerHtml ?? '';
        case 'innerHTML':
          result = doc?.innerHtml ?? '';
        default:
          result = doc?.outerHtml ?? '';
      }
      return result;
    }

    jsQueryXPath(args) {
      final content = args[0];
      final selector = args[1];
      final fun = args[2];

      final xpath = HtmlXPath.html(content);
      final result = xpath.queryXPath(selector);
      String returnVal = '';
      switch (fun) {
        case 'attr':
          returnVal = result.attr ?? '';
        case 'attrs':
          returnVal = jsonEncode(result.attrs);
        case 'text':
          returnVal = result.node?.text ?? '';
        case 'allHTML':
          returnVal = result.nodes
              .map((e) => (e.node as Element).outerHtml)
              .toList()
              .toString();
        case 'outerHTML':
          returnVal = (result.node?.node as Element).outerHtml;
        default:
          returnVal = result.node?.text ?? "";
      }
      return returnVal;
    }

    jsRemoveSelector(dynamic args) {
      final content = args[0];
      final selector = args[1];
      final doc = parse(content);
      doc.querySelectorAll(selector).forEach((element) {
        element.remove();
      });
      return doc.outerHtml;
    }

    jsGetAttributeText(args) {
      final content = args[0];
      final selector = args[1];
      final attr = args[2];
      final doc = parse(content).querySelector(selector);
      return doc?.attributes[attr];
    }

    jsQuerySelectorAll(dynamic args) async {
      final content = args["content"];
      final selector = args["selector"];
      final doc = parse(content).querySelectorAll(selector);
      final elements = jsonEncode(doc.map((e) {
        return e.outerHtml;
      }).toList());
      return elements;
    }

    runtime.onMessage('getSetting', (dynamic args) => jsGetMessage(args));
    // 日志
    runtime.onMessage('log', (args) => jsLog(args));
    // 请求
    runtime.onMessage('request', (args) => jsRequest(args));
    // 设置
    runtime.onMessage('registerSetting', (args) => jsRegisterSetting(args));
    runtime.onMessage('setSetting', (args) => jsSetSetting(args));
    // 清理扩展设置
    runtime.onMessage('cleanSettings', (dynamic args) => jsCleanSettings(args));
    // xpath 选择器
    runtime.onMessage('queryXPath', (arg) => jsQueryXPath(arg));
    runtime.onMessage('removeSelector', (args) => jsRemoveSelector(args));
    // 获取标签属性
    runtime.onMessage('getAttributeText', (args) => jsGetAttributeText(args));
    runtime.onMessage(
        'querySelectorAll', (dynamic args) => jsQuerySelectorAll(args));
    // css 选择器
    runtime.onMessage('querySelector', (arg) => jsQuerySelector(arg));
    if (Platform.isLinux) {
      handleDartBridge(String channelName, Function fn) {
        jsBridge.setHandler(channelName, (message) async {
          final args = jsonDecode(message);
          final result = await fn(args);
          await jsBridge.sendMessage(channelName, result);
        });
      }

      jsBridge = JsBridge(jsRuntime: runtime);
      handleDartBridge('cleanSettings$className', jsCleanSettings);
      handleDartBridge('request$className', jsRequest);
      handleDartBridge('log$className', jsLog);
      handleDartBridge('queryXPath$className', jsQueryXPath);
      handleDartBridge('removeSelector$className', jsRemoveSelector);
      handleDartBridge("getAttributeText$className", jsGetAttributeText);
      handleDartBridge('querySelectorAll$className', jsQuerySelectorAll);
      handleDartBridge('querySelector$className', jsQuerySelector);
      handleDartBridge('registerSetting$className', jsRegisterSetting);
      handleDartBridge('getSetting$className', jsGetMessage);
      handleDartBridge('setSetting$className', jsSetSetting);
    }
    // 初始化运行扩展
    await _initRunExtension(content);
    supportsLogin = await _isLoginSupported();
    await refreshLoginStatus();
    return this;
  }

  _initRunExtension(String extScript) async {
    final cryptoJs = await rootBundle.loadString('assets/js/CryptoJS.min.js');
    final jsencrypt = await rootBundle.loadString('assets/js/jsencrypt.min.js');
    final md5 = await rootBundle.loadString('assets/js/md5.min.js');
    runtime.evaluate(Platform.isLinux
        ? '''
$cryptoJs
$jsencrypt
$md5
class Element {
  constructor(content, selector) {
    this.content = content;
    this.selector = selector || "";
  }
  async querySelector(selector) {
    return new Element(await this.execute(), selector);
  }

  async execute(fun) {
    return await handlePromise("querySelector$className",JSON.stringify([this.content, this.selector, fun]));
  }

  async removeSelector(selector) {
    this.content = await handlePromise("removeSelector$className",JSON.stringify([await this.outerHTML, selector]));
    return this;
  }

  async getAttributeText(attr) {
    return await handlePromise("getAttributeText$className",JSON.stringify([await this.outerHTML, this.selector, attr]));
  }

  get text() {
    return this.execute("text");
  }

  get outerHTML() {
    return this.execute("outerHTML");
  }

  get innerHTML() {
    return this.execute("innerHTML");
  }
}
class XPathNode {
  constructor(content, selector) {
    this.content = content;
    this.selector = selector;
  }

  async excute(fun) {
    return await handlePromise("queryXPath$className",JSON.stringify([this.content, this.selector, fun]));
  }

  get attr() {
    return this.excute("attr");
  }

  get attrs() {
    return this.excute("attrs");
  }

  get text() {
    return this.excute("text");
  }
  
  get allHTML() {
    return this.excute("allHTML");
  }

  get outerHTML() {
    return this.excute("outerHTML");
  }
}

// 重写 console.log
console.log = function (message) {
  if (typeof message === "object") {
    message = JSON.stringify(message);
  }
  DartBridge.sendMessage("log$className", JSON.stringify([message.toString()]));
};
class Extension {
  package = "${extension.package}";
  name = "${extension.name}";
  // 在 load 中注册的 keys
  settingKeys = [];
  
  querySelector(content, selector) {
    return new Element(content, selector);
  }
   async request(url, options) {
    options = options || {};
    options.headers = options.headers || {};
    const miruUrl = options.headers["Miru-Url"] || "${extension.webSite}";
    options.method = options.method || "get";
    const message = await handlePromise("request$className",JSON.stringify([miruUrl + url, options,"${extension.package}"]));
    try {
      return JSON.parse(message);
    }catch(e){
      return message;
    }
  }
  queryXPath(content, selector) {
    return new XPathNode(content, selector);
  }
  async querySelectorAll(content, selector) {
    const arg = await handlePromise("querySelectorAll$className",JSON.stringify({content:content, selector:selector}));
    const message = JSON.parse(arg);
    const elements = [];
    for(const e of message){
      elements.push(new Element(e, selector));
    }
    return elements;
  }
  async getAttributeText(content, selector, attr) {
    const waitForChange  = new Promise(resolve=>{DartBridge.setHandler("getAttributeText$className", async (arg) => {
      resolve(arg);
    })});
    DartBridge.sendMessage("getAttributeText$className",  JSON.stringify([content, selector, attr]));
    const elements = await waitForChange;
    return elements;
  }
  latest(page) {
    throw new Error("not implement latest");
  }
  search(kw, page, filter) {
    throw new Error("not implement search");
  }
  createFilter(filter){
    throw new Error("not implement createFilter");
  }
  detail(url) {
    throw new Error("not implement detail");
  }
  watch(url) {
    throw new Error("not implement watch");
  }
  checkUpdate(url) {
    throw new Error("not implement checkUpdate");
  }
  async getSetting(key) {
    return await handlePromise("getSetting$className",JSON.stringify([key]));
  }
  async registerSetting(settings) {
    console.log(JSON.stringify([settings]));
    this.settingKeys.push(settings.key);
    return await handlePromise("registerSetting$className",JSON.stringify([settings]));
  }
  async setSetting(key, value) {
    return await handlePromise("setSetting$className",JSON.stringify([key, value]));
  }
  login() { return null; }
  loginForm() { return []; }
  sendVerificationCode(field, values) { throw new Error("verification code is not supported"); }
  submitLogin(values) { throw new Error("not implement submitLogin"); }
  isLoginSupported() { return false; }
  getLoginStatus() { return null; }
  async load() {}
}
async function handlePromise(channelName,message){
  const waitForChange  = new Promise(resolve=>{DartBridge.setHandler(channelName, async (arg) => {
    resolve(arg);
  })});
  DartBridge.sendMessage(channelName,  message);
  return await waitForChange
}
async function stringify(callback) {
  const data = await callback();
  return typeof data === "object" ? JSON.stringify(data,0,2) : data;
}



            '''
        : '''
          // 重写 console.log
          var window = (global = globalThis);
          $cryptoJs
          $jsencrypt
          $md5
          class Element {
            constructor(content, selector) {
              this.content = content;
              this.selector = selector || "";
            }

            async querySelector(selector) {
              return new Element(await this.excute(), selector);
            }

            async excute(fun) {
              return await sendMessage(
                "querySelector",
                JSON.stringify([this.content, this.selector, fun])
              );
            }

            async removeSelector(selector) {
              this.content = await sendMessage(
                "removeSelector",
                JSON.stringify([await this.outerHTML, selector])
              );
              return this;
            }

            async getAttributeText(attr) {
              return await sendMessage(
                "getAttributeText",
                JSON.stringify([await this.outerHTML, this.selector, attr])
              );
            }

            get text() {
              return this.excute("text");
            }

            get outerHTML() {
              return this.excute("outerHTML");
            }

            get innerHTML() {
              return this.excute("innerHTML");
            }
          }
          class XPathNode {
            constructor(content, selector) {
              this.content = content;
              this.selector = selector;
            }

            async excute(fun) {
              return await sendMessage(
                "queryXPath",
                JSON.stringify([this.content, this.selector, fun])
              );
            }

            get attr() {
              return this.excute("attr");
            }

            get attrs() {
              return this.excute("attrs");
            }

            get text() {
              return this.excute("text");
            }
            
            get allHTML() {
              return this.excute("allHTML");
            }

            get outerHTML() {
              return this.excute("outerHTML");
            }
          }

          
          console.log = function (message) {
            if (typeof message === "object") {
              message = JSON.stringify(message);
            }
            sendMessage("log", JSON.stringify([message.toString()]));
          };
          class Extension {
            package = "${extension.package}";
            name = "${extension.name}";
            // 在 load 中注册的 keys
            settingKeys = [];
            async request(url, options) {
              options = options || {};
              options.headers = options.headers || {};
              const miruUrl = options.headers["Miru-Url"] || "${extension.webSite}";
              options.method = options.method || "get";
              const res = await sendMessage(
                "request",
                JSON.stringify([miruUrl + url, options])
              );
              try {
                return JSON.parse(res);
              } catch (e) {
                return res;
              }
            }
            querySelector(content, selector) {
              return new Element(content, selector);
            }
            queryXPath(content, selector) {
              return new XPathNode(content, selector);
            }
            async querySelectorAll(content, selector) {
              let elements = [];
              JSON.parse(
                await sendMessage("querySelectorAll", JSON.stringify({content:content,selector:selector}))
              ).forEach((e) => {
                elements.push(new Element(e, selector));
              });
              return elements;
            }
            async getAttributeText(content, selector, attr) {
              return await sendMessage(
                "getAttributeText",
                JSON.stringify([content, selector, attr])
              );
            }
            popular(page) {
              throw new Error("not implement popular");
            }
            latest(page) {
              throw new Error("not implement latest");
            }
            search(kw, page, filter) {
              throw new Error("not implement search");
            }
            createFilter(filter){
              throw new Error("not implement createFilter");
            }
            detail(url) {
              throw new Error("not implement detail");
            }
            watch(url) {
              throw new Error("not implement watch");
            }
            musicSearch(keyword, page, filter) {
              throw new Error("not implement musicSearch");
            }
            musicFilters(filter) {
              throw new Error("not implement musicFilters");
            }
            musicDetail(url) {
              throw new Error("not implement musicDetail");
            }
            musicPlay(url) {
              throw new Error("not implement musicPlay");
            }
            musicLyrics(url) {
              throw new Error("not implement musicLyrics");
            }
            checkUpdate(url) {
              throw new Error("not implement checkUpdate");
            }
            async getSetting(key) {
              return sendMessage("getSetting", JSON.stringify([key]));
            }
            async registerSetting(settings) {
              console.log(JSON.stringify([settings]));
              this.settingKeys.push(settings.key);
              return sendMessage("registerSetting", JSON.stringify([settings]));
            }
            async setSetting(key, value) {
              return sendMessage("setSetting", JSON.stringify([key, value]));
            }
            async load() {}
            login() {
              return null;
            }
            loginForm() {
              return [];
            }
            sendVerificationCode(field, values) {
              throw new Error("verification code is not supported");
            }
            submitLogin(values) {
              throw new Error("not implement submitLogin");
            }
            isLoginSupported() {
              return false;
            }
            getLoginStatus() {
              return null;
            }
          }

          async function stringify(callback) {
            const data = await callback();
            return typeof data === "object" ? JSON.stringify(data,0,2) : data;
          }
    ''');

    final ext = extScript.replaceAll(RegExp(r'export default class.*'),
        'class $className extends Extension {');

    runtime.evaluate('''
      $ext
      if(typeof ${className}Instance !== 'undefined'){
        delete ${className}Instance;
      }
      var ${className}Instance = new $className();
      ${className}Instance.load().then(()=>{
        if(${Platform.isLinux}){
           DartBridge.sendMessage("cleanSettings$className",JSON.stringify([extension.settingKeys]));
        }
        sendMessage("cleanSettings", JSON.stringify([extension.settingKeys]));
      });
    ''');
    isinit = true;
  }

  // 清理 cookie
  cleanCookie() async {
    await MiruRequest.cleanCookie(extension.webSite);
  }

  /// 添加 cookie
  /// key=value; key=value
  setCookie(String cookies) async {
    await MiruRequest.setCookie(cookies, extension.webSite);
  }

  // 列出所有的 cookie
  Future<String> listCookie() async {
    return await MiruRequest.getCookie(extension.webSite);
  }

  Future<T> runExtension<T>(Future<T> Function() fun) async {
    try {
      return await fun();
    } catch (e) {
      ExtensionUtils.addLog(
        extension,
        ExtensionLogLevel.error,
        e.toString(),
      );
      rethrow;
    }
  }

  Future<Map<String, String>> get _defaultHeaders async {
    return {
      "Referer": _cuurentRequestUrl,
      "User-Agent": MiruStorage.getUASetting(),
      "Cookie": await listCookie(),
    };
  }

  Future<List<ExtensionListItem>> latest(int page) async {
    return runExtension(() async {
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(Platform.isLinux
            ? '${className}Instance.latest($page)'
            : 'stringify(()=>${className}Instance.latest($page))'),
      );

      List<ExtensionListItem> result =
          jsonDecode(jsResult.stringResult).map<ExtensionListItem>((e) {
        return ExtensionListItem.fromJson(e);
      }).toList();
      for (var element in result) {
        element.headers ??= await _defaultHeaders;
      }
      return result;
    });
  }

  Future<List<ExtensionListItem>> search(
    String kw,
    int page, {
    Map<String, List<String>>? filter,
  }) async {
    return runExtension(() async {
      final invocation = extensionJsCall(
        className,
        'search',
        [kw, page, filter ?? <String, List<String>>{}],
      );
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(
          Platform.isLinux ? invocation : 'stringify(()=>$invocation)',
        ),
      );
      List<ExtensionListItem> result =
          jsonDecode(jsResult.stringResult).map<ExtensionListItem>((e) {
        return ExtensionListItem.fromJson(e);
      }).toList();
      for (var element in result) {
        element.headers ??= await _defaultHeaders;
      }
      return result;
    });
  }

  Future<Map<String, ExtensionFilter>> createFilter({
    Map<String, List<String>>? filter,
  }) async {
    late String eval;
    if (filter == null) {
      eval = Platform.isLinux
          ? '${className}Instance.createFilter()'
          : 'stringify(()=>${className}Instance.createFilter())';
    } else {
      final invocation = extensionJsCall(
        className,
        'createFilter',
        [filter],
      );
      eval = Platform.isLinux ? invocation : 'stringify(()=>$invocation)';
    }
    return runExtension(() async {
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(eval),
      );
      Map<String, dynamic> result = jsonDecode(jsResult.stringResult);
      return result.map(
        (key, value) => MapEntry(
          key,
          ExtensionFilter.fromJson(value),
        ),
      );
    });
  }

  Future<ExtensionDetail> detail(String url) async {
    return runExtension(() async {
      final invocation = extensionJsCall(className, 'detail', [url]);
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(
          Platform.isLinux ? invocation : 'stringify(()=>$invocation)',
        ),
      );
      final result =
          ExtensionDetail.fromJson(jsonDecode(jsResult.stringResult));
      result.headers ??= await _defaultHeaders;
      return result;
    });
  }

  Future<Object?> watch(String url) async {
    try {
      return await runExtension(() async {
        final invocation = extensionJsCall(className, 'watch', [url]);
        final jsResult = await runtime.handlePromise(
          await runtime.evaluateAsync(
            Platform.isLinux ? invocation : 'stringify(()=>$invocation)',
          ),
        );
        final data = jsonDecode(jsResult.stringResult);

        switch (extension.type) {
          case ExtensionType.bangumi:
            final result = ExtensionBangumiWatch.fromJson(data);
            final defaults = await _defaultHeaders;
            result.headers = {
              ...defaults,
              ...?result.headers,
            };
            return result;
          case ExtensionType.manga:
            final result = ExtensionMangaWatch.fromJson(data);
            result.headers ??= await _defaultHeaders;
            return result;
          case ExtensionType.fikushon:
            return ExtensionFikushonWatch.fromJson(data);
          case ExtensionType.music:
            throw StateError(
                'Music extensions use musicStream() instead of watch()');
        }
      });
    } catch (_) {
      // watch() 过程中插件可能因为服务端返回 unauthorized 而主动清
      // 除本地 token（见 cycani.js 的 _clearAuth 等实现），这里触发
      // 一次登录状态刷新，让 Settings 页等依赖 isLoggedIn 的 UI 及时
      // 反映真实状态，避免「设置页显示已登录但播放报错」的不一致。
      if (supportsLogin) {
        unawaited(refreshLoginStatus());
      }
      rethrow;
    }
  }

  Future<bool> _isLoginSupported() async {
    try {
      final result = await _evaluateMusic('isLoginSupported', []);
      return jsonDecode(result.stringResult) == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> loginConfig() async {
    if (extension.package == 'org.cycani') {
      return {'mode': 'form'};
    }
    return runExtension(() async {
      final result = await _evaluateMusic('login', []);
      final data = jsonDecode(result.stringResult);
      if (data == null) {
        return {'mode': 'webview', 'url': extension.webSite};
      }
      if (data is String) {
        return {'mode': 'webview', 'url': data};
      }
      final config = Map<String, dynamic>.from(data as Map);
      final mode = config['mode'] as String? ?? 'webview';
      if (!{'webview', 'form'}.contains(mode)) {
        throw FormatException('Unsupported login mode: $mode');
      }
      return {
        ...config,
        'mode': mode,
        'url': config['url'] as String? ?? extension.webSite,
      };
    });
  }

  Future<String?> login() async => (await loginConfig())['url'] as String?;

  Future<List<Map<String, dynamic>>> loginForm() async {
    if (extension.package == 'org.cycani') {
      return [
        {
          'key': 'username',
          'label': '账号',
          'type': 'text',
          'placeholder': '请输入账号',
        },
        {
          'key': 'password',
          'label': '密码',
          'type': 'password',
          'placeholder': '请输入密码',
        },
      ];
    }
    return runExtension(() async {
      final result = await _evaluateMusic('loginForm', []);
      final data = jsonDecode(result.stringResult);
      if (data == null) {
        return <Map<String, dynamic>>[];
      }
      if (data is! List) {
        throw const FormatException('loginForm must return a list');
      }
      return data
          .map((field) => Map<String, dynamic>.from(field as Map))
          .toList();
    });
  }

  Future<String> sendLoginVerificationCode(
    String field,
    Map<String, String> values,
  ) async {
    final result =
        await _evaluateMusic('sendVerificationCode', [field, values]);
    return jsonDecode(result.stringResult)?.toString() ?? '验证码已发送';
  }

  /// 读取扩展设置。
  ///
  /// JS 桥接返回的是数据库中存储的原始字符串（例如 JWT 令牌），并不是
  /// JSON 编码后的文本，因此这里不能使用 jsonDecode，否则形如
  /// `eyJhbGci...` 的令牌会抛出 FormatException，被上层误判为未登录。
  Future<String?> getSetting(String key) async {
    final result = await _evaluateMusic('getSetting', [key]);
    final value = result.stringResult;
    if (value == 'null' || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  Future<bool> submitLogin(Map<String, String> values) async {
    final result = await _evaluateMusic('submitLogin', [values]);
    final success = jsonDecode(result.stringResult) == true;
    if (success) await refreshLoginStatus();
    return success;
  }

  /// 读取插件通过可选契约 `getLoginStatus()` 上报的登录状态。
  ///
  /// 约定返回：
  /// - `{ loggedIn: true, user?: string }` 表示已登录；
  /// - `{ loggedIn: false }` 表示未登录；
  /// - `null` 表示插件未实现该契约，调用方应回退到通用设置键判断。
  Future<Map<String, dynamic>?> _readLoginStatusFromExtension() async {
    try {
      final result = await _evaluateMusic('getLoginStatus', []);
      final raw = result.stringResult;
      if (raw.isEmpty || raw == 'null') {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshLoginStatus() async {
    bool nextLoggedIn = false;
    String? nextUserLabel;
    try {
      final status = await _readLoginStatusFromExtension();
      if (status != null) {
        nextLoggedIn = status['loggedIn'] == true;
        final user = status['user'] ?? status['username'];
        final label = user?.toString().trim();
        nextUserLabel = (label == null || label.isEmpty) ? null : label;
      } else {
        // 回退方案：未实现 getLoginStatus 契约的插件，
        // 通过通用认证设置键判断登录状态。
        final token = await getSetting('authToken');
        final user = await getSetting('authUser');
        final expiresAt = await getSetting('authExpiresAt');
        final validExpiry = expiresAt == null ||
            (int.tryParse(expiresAt) ?? 0) >
                DateTime.now().millisecondsSinceEpoch;
        nextLoggedIn = token != null && validExpiry;
        final label = user?.trim();
        nextUserLabel = (label == null || label.isEmpty) ? null : label;
      }
    } catch (_) {
      nextLoggedIn = false;
      nextUserLabel = null;
    }
    if (isLoggedIn != nextLoggedIn || loginUserLabel != nextUserLabel) {
      isLoggedIn = nextLoggedIn;
      loginUserLabel = nextUserLabel;
      notifyListeners();
    }
  }

  Future<MusicSearchResult> musicSearch(
    String keyword,
    int page, {
    Map<String, List<String>>? filter,
  }) async {
    return runExtension(() async {
      final result = await _evaluateMusic(
        'musicSearch',
        [keyword, page, filter],
      );
      return MusicSearchResult.fromJson(jsonDecode(result.stringResult));
    });
  }

  Future<Map<String, MusicFilter>> musicFilters({
    Map<String, List<String>>? filter,
  }) async {
    return runExtension(() async {
      final result = await _evaluateMusic('musicFilters', [filter]);
      final data =
          Map<String, dynamic>.from(jsonDecode(result.stringResult) as Map);
      return data.map(
        (key, value) => MapEntry(
          key,
          MusicFilter.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      );
    });
  }

  Future<MusicDetail> musicDetail(String url) async {
    return runExtension(() async {
      final result = await _evaluateMusic('musicDetail', [url]);
      return MusicDetail.fromJson(jsonDecode(result.stringResult));
    });
  }

  Future<MusicStream> musicStream(String url) async {
    return runExtension(() async {
      final result = await _evaluateMusic('musicPlay', [url]);
      final data = jsonDecode(result.stringResult);
      if (data is String) return MusicStream(url: data);
      return MusicStream.fromJson(Map<String, dynamic>.from(data as Map));
    });
  }

  Future<String> musicLyrics(String url) async {
    return runExtension(() async {
      final result = await _evaluateMusic('musicLyrics', [url]);
      final data = jsonDecode(result.stringResult);
      return data is String ? data : (data['lyrics'] as String? ?? '');
    });
  }

  Future<dynamic> _evaluateMusic(String method, List<dynamic> args) async {
    final invocation = extensionJsCall(className, method, args);
    final expression = Platform.isLinux
        ? invocation
        : extensionJsPromiseCall(className, method, args);
    return runtime.handlePromise(await runtime.evaluateAsync(expression));
  }

  Future<String> debugExecute(String method) async {
    final expression =
        'stringify(() => ${className}Instance[${jsonEncode(method)}]())';
    final result = await runtime.handlePromise(
      await runtime.evaluateAsync(expression),
    );
    return result.stringResult;
  }

  Future<String> checkUpdate(url) async {
    return runExtension(() async {
      final jsResult = await runtime.handlePromise(
        await runtime.evaluateAsync(
            'stringify(()=>${className}Instance.checkUpdate("$url"))'),
      );
      return jsResult.stringResult;
    });
  }
}
