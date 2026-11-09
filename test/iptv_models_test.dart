import 'package:flutter_test/flutter_test.dart';
import 'package:tvexp_iptv/core/models/iptv_models.dart';
import 'package:tvexp_iptv/core/services/m3u_parser.dart';

void main() {
  group('XtreamCredentials', () {
    test('adds HTTPS when the scheme is omitted', () {
      const credentials = XtreamCredentials(server: 'portal.example:8080/', username: 'u', password: 'p');
      expect(credentials.normalizedServer, 'https://portal.example:8080');
    });
    test('preserves explicitly selected HTTP', () {
      const credentials = XtreamCredentials(server: 'http://portal.example:8080', username: 'u', password: 'p');
      expect(credentials.normalizedServer, 'http://portal.example:8080');
    });
    test('rejects an invalid server URL', () {
      const credentials = XtreamCredentials(server: 'not a valid host', username: 'u', password: 'p');
      expect(() => credentials.normalizedServer, throwsFormatException);
    });
  });

  test('maps Xtream VOD records into media items', () {
    final item = MediaItem.fromJson({'stream_id':42,'name':'Example Movie','stream_icon':'https://img.example/poster.jpg','container_extension':'mkv','category_id':'7'}, CatalogSection.movies);
    expect(item.id, '42'); expect(item.name, 'Example Movie'); expect(item.image, 'https://img.example/poster.jpg'); expect(item.extension, 'mkv'); expect(item.categoryId, '7');
  });

  group('M3uParser', () {
    test('parses extended info, logo, group and URL', () {
      const playlist = '#EXTM3U\n#EXTINF:-1 tvg-id="one" tvg-name="News HD" tvg-logo="https://img.test/logo.png" group-title="News",News HD\nhttps://stream.test/live/1.m3u8\n';
      final items = M3uParser.parse(playlist);
      expect(items, hasLength(1)); expect(items.first.name, 'News HD'); expect(items.first.group, 'News'); expect(items.first.image, 'https://img.test/logo.png'); expect(items.first.url, 'https://stream.test/live/1.m3u8');
    });
    test('ignores unsupported local file entries', () {
      const playlist = '#EXTM3U\n#EXTINF:-1,Local\nfile:///tmp/a.ts\n';
      expect(M3uParser.parse(playlist), isEmpty);
    });
    test('classifies common video files as VOD', () {
      const playlist = '#EXTM3U\n#EXTINF:-1 group-title="Movies",Film\nhttps://cdn.test/film.mp4\n';
      expect(M3uParser.parse(playlist).single.section, CatalogSection.movies);
    });
  });
}
