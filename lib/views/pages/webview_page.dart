import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:miru_app/data/services/extension_service.dart';
import 'package:miru_app/utils/miru_storage.dart';

class WebViewPage extends StatefulWidget {
  const WebViewPage({
    super.key,
    required this.extensionRuntime,
    required this.url,
  });
  final ExtensionService extensionRuntime;
  final String url;

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late String url = Uri.parse(widget.url).hasScheme
      ? widget.url
      : widget.extensionRuntime.extension.webSite + widget.url;
  final cookieManager = CookieManager.instance();
  late Uri loadUrl = Uri.parse(url);

  Future<void> _setCookie(String currentUrl) async {
    final currentUri = Uri.tryParse(currentUrl);
    final siteHost = Uri.parse(widget.extensionRuntime.extension.webSite).host;
    if (currentUri == null ||
        (currentUri.host != siteHost &&
            !currentUri.host.endsWith('.$siteHost'))) {
      return;
    }
    final cookies = await cookieManager.getCookies(url: WebUri(currentUrl));
    final cookieString = cookies.map((e) => '${e.name}=${e.value}').join(';');
    if (cookieString.isNotEmpty) {
      await widget.extensionRuntime.setCookie(cookieString);
    }
  }

  @override
  void dispose() {
    _setCookie(loadUrl.toString());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(loadUrl.toString()),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(url),
        ),
        initialSettings: InAppWebViewSettings(
          userAgent: MiruStorage.getUASetting(),
        ),
        onLoadStart: (controller, url) {
          if (url == null) return;
          setState(() {
            loadUrl = url;
          });
          _setCookie(url.toString());
        },
        onLoadStop: (controller, url) {
          if (url != null) _setCookie(url.toString());
        },
      ),
    );
  }
}
