enum CatalogSection { live, movies, series, downloads }
enum PlaylistType { xtream, m3u }

class XtreamCredentials {
  const XtreamCredentials({required this.server, required this.username, required this.password});
  final String server;
  final String username;
  final String password;
  String get normalizedServer {
    var value = server.trim().replaceFirst(RegExp(r'/+$'), '');
    if (value.isEmpty) {
      throw const FormatException('عنوان السيرفر غير صحيح');
    }
    if (!value.contains('://')) value = 'https://$value';

    // A server address must not contain whitespace. Uri.parse is permissive
    // and may accept values such as "https://not a valid host" as a URI.
    if (value.contains(RegExp(r'\s'))) {
      throw const FormatException('عنوان السيرفر غير صحيح');
    }

    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('عنوان السيرفر غير صحيح');
    }
    return value;
  }
}

class PlaylistProfile {
  const PlaylistProfile({required this.id, required this.name, required this.type, required this.source, this.username = '', this.password = '', this.lastConnectedAt, this.isActive = false});
  final String id, name, source, username, password;
  final PlaylistType type;
  final DateTime? lastConnectedAt;
  final bool isActive;
  Map<String, dynamic> toJson() => {'id':id,'name':name,'type':type.name,'source':source,'username':username,'password':password,'lastConnectedAt':lastConnectedAt?.toIso8601String(),'isActive':isActive};
  factory PlaylistProfile.fromJson(Map<String,dynamic> j) => PlaylistProfile(id:'${j['id']}', name:'${j['name']}', type: PlaylistType.values.firstWhere((e)=>e.name==j['type'],orElse:()=>PlaylistType.xtream), source:'${j['source']}', username:'${j['username']??''}', password:'${j['password']??''}', lastConnectedAt: DateTime.tryParse('${j['lastConnectedAt']??''}'), isActive:j['isActive']==true);
}

class MediaItem {
  const MediaItem({required this.id, required this.name, required this.section, this.image, this.categoryId, this.extension, this.url, this.group, this.raw = const {}});
  final String id, name;
  final CatalogSection section;
  final String? image, categoryId, extension, url, group;
  final Map<String, dynamic> raw;
  factory MediaItem.fromJson(Map<String, dynamic> json, CatalogSection section) {
    final id = json['stream_id'] ?? json['series_id'] ?? json['id'] ?? '';
    return MediaItem(id:id.toString(), name:(json['name'] ?? json['title'] ?? 'بدون اسم').toString(), section:section, image:(json['stream_icon'] ?? json['cover'] ?? json['movie_image'] ?? json['cover_big'])?.toString(), categoryId:json['category_id']?.toString(), extension:json['container_extension']?.toString(), url:(json['url'] ?? json['stream_url'])?.toString(), group:(json['group-title'] ?? json['group'])?.toString(), raw:json);
  }
}
class MediaCategory {
  const MediaCategory({required this.id, required this.name});
  final String id, name;
  factory MediaCategory.fromJson(Map<String,dynamic> j)=>MediaCategory(id:'${j['category_id']??j['id']??''}',name:'${j['category_name']??j['name']??'غير مصنف'}');
}
