import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:miru_app/controllers/music_controller.dart';
import 'package:miru_app/models/index.dart';
import 'package:miru_app/data/services/extension_service.dart';
import 'package:miru_app/views/widgets/platform_widget.dart';

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  late final MusicPlayerController player;
  final keyword = TextEditingController();
  final results = <MusicTrack>[].obs;
  final loading = false.obs;
  final filters = <String, MusicFilter>{}.obs;
  final selectedFilters = <String, List<String>>{}.obs;
  String? selectedPackage;
  int page = 1;

  ExtensionService? get selectedRuntime {
    final runtimes = player.musicRuntimes;
    if (runtimes.isEmpty) return null;
    selectedPackage ??= runtimes.first.extension.package;
    return runtimes.firstWhere(
      (runtime) => runtime.extension.package == selectedPackage,
      orElse: () => runtimes.first,
    );
  }

  @override
  void initState() {
    super.initState();
    player = Get.isRegistered<MusicPlayerController>()
        ? Get.find<MusicPlayerController>()
        : Get.put(MusicPlayerController());
    WidgetsBinding.instance.addPostFrameCallback((_) => _selectRuntime());
  }

  Future<void> _selectRuntime([ExtensionService? runtime]) async {
    final selected = runtime ?? selectedRuntime;
    if (selected == null) return;
    setState(() => selectedPackage = selected.extension.package);
    filters.clear();
    selectedFilters.clear();
    try {
      final data = await selected.musicFilters();
      filters.addAll(data);
      selectedFilters.addAll({
        for (final entry in data.entries)
          entry.key: [entry.value.defaultOption],
      });
    } catch (_) {
      filters.clear();
      selectedFilters.clear();
    }
    await search();
  }

  Future<void> search() async {
    final runtime = selectedRuntime;
    if (runtime == null) return;
    loading.value = true;
    try {
      final data = await runtime.musicSearch(
        keyword.text.trim(),
        page,
        filter: selectedFilters.isEmpty ? null : selectedFilters,
      );
      results.assignAll(data.items);
    } finally {
      loading.value = false;
    }
  }

  Future<void> _selectFilter(String key, String value) async {
    final current = Map<String, List<String>>.from(selectedFilters);
    final values = List<String>.from(current[key] ?? []);
    final filter = filters[key]!;
    if (values.contains(value)) {
      if (values.length > filter.min) values.remove(value);
    } else {
      if (values.length >= filter.max) values.removeAt(0);
      values.add(value);
    }
    current[key] = values;
    final runtime = selectedRuntime;
    if (runtime == null) return;
    final updated = await runtime.musicFilters(filter: current);
    setState(() {
      filters
        ..clear()
        ..addAll(updated);
      selectedFilters
        ..clear()
        ..addAll({
          for (final entry in updated.entries)
            entry.key: List<String>.from(current[entry.key] ?? [entry.value.defaultOption]),
        });
    });
    await search();
  }

  void _openFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('分类与筛选', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            for (final entry in filters.entries) ...[
              Text(entry.value.title),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in entry.value.options.entries)
                    FilterChip(
                      label: Text(option.value),
                      selected: selectedFilters[entry.key]?.contains(option.key) ?? false,
                      onSelected: (_) async {
                        await _selectFilter(entry.key, option.key);
                        if (context.mounted) setState(() {});
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _pluginBar() => SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: player.musicRuntimes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final runtime = player.musicRuntimes[index];
            final selected = runtime.extension.package == selectedPackage;
            return ChoiceChip(
              label: Text(runtime.extension.name),
              selected: selected,
              onSelected: (_) => _selectRuntime(runtime),
            );
          },
        ),
      );

  Widget _trackTile(MusicTrack track) => ListTile(
        leading: track.cover == null
            ? const Icon(Icons.music_note)
            : Image.network(track.cover!, width: 48, height: 48, fit: BoxFit.cover),
        title: Text(track.title),
        subtitle: Text([track.artist, track.album].whereType<String>().join(' · ')),
        trailing: const Icon(Icons.play_arrow),
        onTap: () async {
          final runtime = selectedRuntime;
          if (runtime != null) await player.playTrack(track, runtime);
        },
      );

  Widget _body(BuildContext context, {required bool desktop}) => Obx(
        () => Column(children: [
          _pluginBar(),
          if (filters.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: desktop
                    ? fluent.IconButton(
                        icon: const Icon(fluent.FluentIcons.filter),
                        onPressed: () => _openFilters(context),
                      )
                    : IconButton(
                        icon: const Icon(Icons.filter_alt),
                        onPressed: () => _openFilters(context),
                      ),
              ),
            ),
          Expanded(
            child: loading.value
                ? const Center(child: CircularProgressIndicator())
                : ListView(children: results.map(_trackTile).toList()),
          ),
          _miniPlayer(),
        ]),
      );

  Widget _android(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('音乐'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: keyword,
                onSubmitted: (_) => search(),
                decoration: const InputDecoration(hintText: '搜索歌曲'),
              ),
            ),
          ),
        ),
        body: _body(context, desktop: false),
      );

  Widget _desktop(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('音乐', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const Spacer(),
            SizedBox(
              width: 320,
              child: fluent.TextBox(
                controller: keyword,
                placeholder: '搜索歌曲',
                onSubmitted: (_) => search(),
              ),
            ),
            const SizedBox(width: 12),
            fluent.FilledButton(onPressed: search, child: const Icon(fluent.FluentIcons.search)),
          ]),
          const SizedBox(height: 12),
          Expanded(child: _body(context, desktop: true)),
        ]),
      );

  Widget _miniPlayer() {
    final track = player.current.value;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      child: Row(children: [
        const Icon(Icons.album, size: 32),
        const SizedBox(width: 12),
        Expanded(child: Text(track?.title ?? '未播放歌曲', overflow: TextOverflow.ellipsis)),
        IconButton(onPressed: player.previous, icon: const Icon(Icons.skip_previous)),
        IconButton(onPressed: player.toggle, icon: const Icon(Icons.play_arrow)),
        IconButton(onPressed: player.next, icon: const Icon(Icons.skip_next)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => PlatformBuildWidget(
        androidBuilder: _android,
        desktopBuilder: _desktop,
      );
}
