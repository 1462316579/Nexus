import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:miru_app/data/providers/anilist_provider.dart';
import 'package:miru_app/models/index.dart';
import 'package:miru_app/views/pages/detail_page.dart';
import 'package:miru_app/views/pages/extension/extension_page.dart';
import 'package:miru_app/views/pages/extension/extension_repo_page.dart';
import 'package:miru_app/views/pages/extension/extension_settings_page.dart';
import 'package:miru_app/views/pages/extension_login_page.dart';
import 'package:miru_app/utils/extension.dart';
import 'package:miru_app/views/pages/favorites_page.dart';
import 'package:miru_app/views/pages/main_page.dart';
import 'package:miru_app/views/pages/content_module_page.dart';
import 'package:miru_app/views/pages/code_edit_page.dart';
import 'package:miru_app/views/pages/library_page.dart';
import 'package:miru_app/views/pages/music_page.dart';
import 'package:miru_app/views/pages/music_plugin_editor_page.dart';
import 'package:miru_app/views/pages/search/extension_searcher_page.dart';
import 'package:miru_app/views/pages/search/search_page.dart';
import 'package:miru_app/views/pages/settings/settings_page.dart';
import 'package:miru_app/views/pages/tracking/anilist_more_page.dart';
import 'package:miru_app/views/pages/tracking/anilist_tracking_page.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

BuildContext get currentContext {
  if (Platform.isAndroid) {
    return Get.context!;
  }
  return _shellNavigatorKey.currentContext!;
}

final router = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) {
        return DesktopMainPage(
          shellContext: _shellNavigatorKey.currentContext,
          state: state,
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => _animation(const ContentModulePage(
            type: ExtensionType.bangumi,
            title: '影视',
          )),
        ),
        GoRoute(
          path: '/manga',
          builder: (context, state) => _animation(const ContentModulePage(
            type: ExtensionType.manga,
            title: '漫画',
          )),
        ),
        GoRoute(
          path: '/novel',
          builder: (context, state) => _animation(const ContentModulePage(
            type: ExtensionType.fikushon,
            title: '小说',
          )),
        ),
        GoRoute(
          path: '/favorites',
          builder: (context, state) => _animation(
            FavoritesPage(
              type: ExtensionType.values[int.parse(
                state.uri.queryParameters['type']!,
              )],
            ),
          ),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) => _animation(const SearchPage()),
        ),
        GoRoute(
          path: '/search_extension',
          builder: (context, state) => _animation(
            ExtensionSearcherPage(
              package: state.uri.queryParameters['package']!,
              keyWord: state.uri.queryParameters['keyWord'],
            ),
          ),
        ),
        GoRoute(
          path: '/extension',
          builder: (context, state) => _animation(const ExtensionPage()),
        ),
        GoRoute(
          path: '/extension_settings',
          builder: (context, state) => _animation(
            ExtensionSettingsPage(
              package: state.uri.queryParameters['package']!,
            ),
          ),
        ),
        GoRoute(
          path: '/extension_login/:package',
          builder: (context, state) {
            final runtime = ExtensionUtils.runtimes[state.pathParameters['package']!];
            if (runtime == null) return const SizedBox.shrink();
            return _animation(ExtensionLoginPage(runtime: runtime));
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => _animation(const SettingsPage()),
        ),
        GoRoute(
          path: '/settings/anilist',
          builder: (context, state) => _animation(const AniListTrackingPage()),
        ),
        GoRoute(
          path: '/settings/anilist_more',
          builder: (context, state) => _animation(
            AnilistMorePage(
              anilistType: AnilistType.values[int.parse(
                state.uri.queryParameters['type']!,
              )],
            ),
          ),
        ),
        GoRoute(
          path: '/extension_repo',
          builder: (context, state) => _animation(const ExtensionRepoPage()),
        ),
        GoRoute(
          path: '/music',
          builder: (context, state) => _animation(const MusicPage()),
        ),
        GoRoute(
          path: '/library/favorites',
          builder: (context, state) => _animation(const LibraryPage(history: false)),
        ),
        GoRoute(
          path: '/library/history',
          builder: (context, state) => _animation(const LibraryPage(history: true)),
        ),
        GoRoute(
          path: '/extension_code',
          builder: (context, state) {
            final package = state.uri.queryParameters['package']!;
            final extension = ExtensionUtils.runtimes[package]?.extension;
            if (extension == null) return const SizedBox.shrink();
            return _animation(CodeEditPage(extension: extension));
          },
        ),
        GoRoute(
          path: '/music/new-plugin',
          builder: (context, state) => _animation(const MusicPluginEditorPage()),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) => _animation(
            DetailPage(
              url: state.uri.queryParameters['url']!,
              package: state.uri.queryParameters['package']!,
            ),
          ),
        ),
      ],
    )
  ],
);

_animation(Widget child) {
  return Animate(
    child: child,
  ).moveY(
    begin: 40,
    end: 0,
    curve: Curves.easeOutCubic,
  );
}
