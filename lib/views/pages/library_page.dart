import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:miru_app/data/services/database_service.dart';
import 'package:miru_app/models/index.dart';
import 'package:miru_app/views/widgets/extension_item_card.dart';
import 'package:miru_app/views/widgets/platform_widget.dart';
import 'package:miru_app/views/widgets/home/home_resent_card.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.history});
  final bool history;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late Future<List<dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = () async {
      if (widget.history) {
        return await DatabaseService.getHistorysByType() as List<dynamic>;
      }
      return await DatabaseService.getFavoritesByType() as List<dynamic>;
    }();
  }

  String get title => widget.history ? '历史记录' : '收藏';

  Widget _desktop(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: fluent.FluentTheme.of(context).typography.title),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.isEmpty) return Center(child: Text('暂无$title'));
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    childAspectRatio: 0.64,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final item = snapshot.data![index];
                    if (widget.history) {
                      final history = item as History;
                      return HomeRecentCard(history: history);
                    }
                    final favorite = item as Favorite;
                    return ExtensionItemCard(
                      title: favorite.title,
                      url: favorite.url,
                      package: favorite.package,
                      cover: favorite.cover,
                    );
                  },
                );
              },
            ),
          ),
        ]),
      );

  Widget _android(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: FutureBuilder<List<dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            if (snapshot.data!.isEmpty) return Center(child: Text('暂无$title'));
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final item = snapshot.data![index];
                if (widget.history) return HomeRecentCard(history: item as History);
                final favorite = item as Favorite;
                return ListTile(title: Text(favorite.title));
              },
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => PlatformBuildWidget(androidBuilder: _android, desktopBuilder: _desktop);
}
