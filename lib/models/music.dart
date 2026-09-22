import 'package:miru_app/models/extension.dart';

class MusicTrack {
  MusicTrack({
    required this.title,
    required this.url,
    this.artist,
    this.album,
    this.cover,
    this.duration,
    this.headers,
    this.id,
  });

  final String title;
  final String url;
  final String? artist;
  final String? album;
  final String? cover;
  final Duration? duration;
  final Map<String, String>? headers;
  final String? id;

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    final duration = json['duration'];
    return MusicTrack(
      title: json['title'] as String? ?? 'Untitled',
      url: json['url'] as String? ?? json['id'] as String? ?? '',
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      cover: json['cover'] as String?,
      duration: duration is num ? Duration(seconds: duration.toInt()) : null,
      headers: json['headers'] == null
          ? null
          : Map<String, String>.from(json['headers'] as Map),
      id: json['id'] as String?,
    );
  }
}

class MusicSearchResult {
  MusicSearchResult({required this.items, this.hasMore = false});

  final List<MusicTrack> items;
  final bool hasMore;

  factory MusicSearchResult.fromJson(dynamic json) {
    if (json is List) {
      return MusicSearchResult(
        items: json
            .whereType<Map>()
            .map((item) => MusicTrack.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
    }
    final data = Map<String, dynamic>.from(json as Map);
    final list = data['items'] ?? data['results'] ?? [];
    return MusicSearchResult(
      items: (list as List)
          .whereType<Map>()
          .map((item) => MusicTrack.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }
}

class MusicFilter {
  MusicFilter({
    required this.title,
    required this.min,
    required this.max,
    required this.defaultOption,
    required this.options,
  });

  final String title;
  final int min;
  final int max;
  final String defaultOption;
  final Map<String, String> options;

  factory MusicFilter.fromJson(Map<String, dynamic> json) => MusicFilter(
        title: json['title'] as String? ?? '',
        min: (json['min'] as num?)?.toInt() ?? 0,
        max: (json['max'] as num?)?.toInt() ?? 1,
        defaultOption: json['default'] as String? ?? '',
        options: Map<String, String>.from(json['options'] as Map? ?? {}),
      );
}

class MusicDetail {
  MusicDetail({required this.title, this.artist, this.album, this.cover, this.tracks});

  final String title;
  final String? artist;
  final String? album;
  final String? cover;
  final List<MusicTrack>? tracks;

  factory MusicDetail.fromJson(Map<String, dynamic> json) => MusicDetail(
        title: json['title'] as String? ?? 'Untitled',
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        cover: json['cover'] as String?,
        tracks: (json['tracks'] as List?)
            ?.whereType<Map>()
            .map((item) => MusicTrack.fromJson(Map<String, dynamic>.from(item)))
            .toList(),
      );
}

class MusicStream {
  MusicStream({required this.url, this.headers, this.lyrics});

  final String url;
  final Map<String, String>? headers;
  final String? lyrics;

  factory MusicStream.fromJson(Map<String, dynamic> json) => MusicStream(
        url: json['url'] as String? ?? '',
        headers: json['headers'] == null
            ? null
            : Map<String, String>.from(json['headers'] as Map),
        lyrics: json['lyrics'] as String?,
      );
}

ExtensionListItem musicTrackToExtensionItem(MusicTrack track) => ExtensionListItem(
      title: track.title,
      url: track.url,
      cover: track.cover,
      headers: track.headers,
    );
