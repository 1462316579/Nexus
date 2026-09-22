import 'package:flutter/material.dart';
import 'package:miru_app/views/pages/code_edit_page.dart';

class MusicPluginEditorPage extends StatelessWidget {
  const MusicPluginEditorPage({super.key});

  static const _template = '''// ==MiruExtension==
// @name         我的音乐插件
// @version      v0.0.1
// @author       Miru User
// @lang         all
// @license      MIT
// @package      com.example.music
// @type         music
// @webSite      https://example.com
// @description  Music extension
// ==/MiruExtension==

export default class MusicExtension extends Extension {
  async musicSearch(keyword, page) {
    return { items: [] };
  }

  async musicDetail(url) {
    return { title: url, tracks: [] };
  }

  async musicPlay(url) {
    return { url: url };
  }

  async musicLyrics(url) {
    return '';
  }
}''';

  @override
  Widget build(BuildContext context) => const CodeEditPage(
        newPlugin: true,
        initialCode: _template,
      );
}
