import '../models/iptv_models.dart';

/// Parses standard extended M3U playlists without assuming a provider-specific format.
class M3uParser {
  static List<MediaItem> parse(String content) {
    final lines = content.replaceAll('\r', '').split('\n');
    final result = <MediaItem>[];
    Map<String, String>? pending;
    var index = 0;
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line == '#EXTM3U') continue;
      if (line.startsWith('#EXTINF:')) {
        pending = _attributes(line);
        final comma = line.indexOf(',');
        pending['name'] = comma >= 0 ? line.substring(comma + 1).trim() : (pending['tvg-name'] ?? 'بدون اسم');
      } else if (!line.startsWith('#') && pending != null) {
        final uri = Uri.tryParse(line);
        if (uri != null && {'http','https','rtmp','rtsp','udp'}.contains(uri.scheme)) {
          final name = (pending['name'] ?? pending['tvg-name'] ?? 'قناة ${index + 1}').trim();
          final group = pending['group-title'] ?? 'غير مصنف';
          final isVod = RegExp(r'\.(mp4|mkv|avi|mov|m4v)(\?|$)', caseSensitive:false).hasMatch(line);
          result.add(MediaItem(id:'m3u_${index++}',name:name,section:isVod?CatalogSection.movies:CatalogSection.live,image:pending['tvg-logo'],url:line,group:group,raw:pending));
        }
        pending = null;
      }
    }
    return result;
  }

  static Map<String,String> _attributes(String line) {
    final result=<String,String>{};
    final pattern=RegExp(r'''([\w-]+)="([^"]*)"|([\w-]+)=([^\s,]+)''');
    for(final m in pattern.allMatches(line.substring(line.indexOf(':')+1))) {
      final key=m.group(1)??m.group(3); final value=m.group(2)??m.group(4);
      if(key!=null && value!=null) result[key]=value;
    }
    return result;
  }
}
