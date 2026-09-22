import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:miru_app/models/index.dart';
import 'package:miru_app/utils/extension.dart';
import 'package:miru_app/data/services/extension_service.dart';

class MusicPlayerController extends GetxController {
  final player = Player();
  final queue = <MusicTrack>[].obs;
  final currentIndex = (-1).obs;
  final current = Rxn<MusicTrack>();
  final lyrics = ''.obs;
  final loading = false.obs;
  final error = ''.obs;

  List<ExtensionService> get musicRuntimes => ExtensionUtils.runtimes.values
      .where((runtime) => runtime.extension.type == ExtensionType.music)
      .toList();

  Future<void> playTrack(MusicTrack track, ExtensionService runtime) async {
    loading.value = true;
    error.value = '';
    try {
      final stream = await runtime.musicStream(track.url);
      final resolved = MusicTrack(
        title: track.title,
        url: stream.url,
        artist: track.artist,
        album: track.album,
        cover: track.cover,
        headers: stream.headers ?? track.headers,
        id: track.id,
      );
      final index = queue.indexWhere((item) => item.url == track.url);
      if (index < 0) {
        queue.add(track);
        currentIndex.value = queue.length - 1;
      } else {
        currentIndex.value = index;
      }
      current.value = resolved;
      lyrics.value = stream.lyrics ?? await runtime.musicLyrics(track.url);
      await player.open(Media(resolved.url, httpHeaders: resolved.headers));
      await player.play();
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
    }
  }

  Future<void> toggle() => player.playOrPause();

  Future<void> next() async {
    if (currentIndex.value + 1 < queue.length) {
      currentIndex.value++;
      final track = queue[currentIndex.value];
      final runtime = musicRuntimes.firstOrNull;
      if (runtime != null) await playTrack(track, runtime);
    }
  }

  Future<void> previous() async {
    if (currentIndex.value > 0) {
      currentIndex.value--;
      final track = queue[currentIndex.value];
      final runtime = musicRuntimes.firstOrNull;
      if (runtime != null) await playTrack(track, runtime);
    }
  }

  @override
  void onClose() {
    player.dispose();
    super.onClose();
  }
}
