import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/iptv_models.dart';
import '../models/epg_program.dart';

class XtreamClient {
  XtreamClient(this.credentials, {http.Client? client}) : _http = client ?? http.Client();
  final XtreamCredentials credentials;
  final http.Client _http;
  Uri get _base => Uri.parse(credentials.normalizedServer);

  Future<Map<String, dynamic>> _get({String? action, Map<String, String> extra = const {}}) async {
    final query = <String, String>{
      'username': credentials.username,
      'password': credentials.password,
      if (action != null) 'action': action,
      ...extra,
    };
    final uri = _base.replace(path: '${_base.path.replaceFirst(RegExp(r'/+$'), '')}/player_api.php', queryParameters: query);
    final response = await _http.get(uri, headers: const {'Accept': 'application/json', 'User-Agent': 'TVEXP-IPTV-Android/2.2'}).timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('فشل الاتصال بالسيرفر: HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) throw const FormatException('استجابة السيرفر غير صالحة');
    return decoded;
  }

  Future<Map<String, dynamic>> authenticate() async {
    final data = await _get();
    final auth = data['user_info']?['auth'];
    if ('$auth' != '1') throw Exception(data['user_info']?['message'] ?? 'بيانات الاشتراك غير صحيحة');
    return data;
  }

  Future<List<MediaCategory>> categories(CatalogSection section) async {
    final action = switch (section) {
      CatalogSection.live => 'get_live_categories',
      CatalogSection.movies => 'get_vod_categories',
      CatalogSection.series => 'get_series_categories',
      CatalogSection.downloads => throw ArgumentError('Downloads have no remote categories'),
    };
    final list = await _getList(action);
    return list.map(MediaCategory.fromJson).toList();
  }

  Future<List<Map<String, dynamic>>> _getList(String action, {String? categoryId}) async {
    final uri = _base.replace(path: '${_base.path.replaceFirst(RegExp(r'/+$'), '')}/player_api.php', queryParameters: {
      'username': credentials.username, 'password': credentials.password, 'action': action,
      if (categoryId != null) 'category_id': categoryId,
    });
    final response = await _http.get(uri).timeout(const Duration(seconds: 35));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('HTTP ${response.statusCode}');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return [];
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<MediaItem>> items(CatalogSection section, {String? categoryId}) async {
    final action = switch (section) {
      CatalogSection.live => 'get_live_streams',
      CatalogSection.movies => 'get_vod_streams',
      CatalogSection.series => 'get_series',
      CatalogSection.downloads => throw ArgumentError('Downloads are local'),
    };
    final rows = await _getList(action, categoryId: categoryId);
    return rows.map((e) => MediaItem.fromJson(e, section)).toList();
  }

  Future<Map<String, dynamic>> seriesInfo(String seriesId) async {
    final uri = _base.replace(path: '${_base.path.replaceFirst(RegExp(r'/+$'), '')}/player_api.php', queryParameters: {
      'username': credentials.username, 'password': credentials.password,
      'action': 'get_series_info', 'series_id': seriesId,
    });
    final response = await _http.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('HTTP ${response.statusCode}');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<List<EpgProgram>> shortEpg(String streamId, {int limit = 20}) async {
    final uri = _base.replace(path: '${_base.path.replaceFirst(RegExp(r'/+$'), '')}/player_api.php', queryParameters: {
      'username': credentials.username,
      'password': credentials.password,
      'action': 'get_short_epg',
      'stream_id': streamId,
      'limit': limit.toString(),
    });
    final response = await _http.get(uri).timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('تعذر تحميل دليل البرامج: HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final rows = decoded is Map ? decoded['epg_listings'] : decoded;
    if (rows is! List) return [];
    final programs = rows.whereType<Map>().map((e) => EpgProgram.fromXtream(Map<String, dynamic>.from(e))).toList();
    programs.sort((a, b) => a.start.compareTo(b.start));
    return programs;
  }

  String streamUrl(MediaItem item) {
    final direct = (item.raw['direct_source'] ?? item.raw['stream_url'] ?? item.raw['url'])?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final root = credentials.normalizedServer;
    final path = switch (item.section) {
      CatalogSection.live => 'live',
      CatalogSection.movies => 'movie',
      CatalogSection.series => 'series',
      CatalogSection.downloads => '',
    };
    final ext = item.extension ?? (item.section == CatalogSection.live ? 'ts' : 'mp4');
    final id = item.raw['stream_id'] ?? item.raw['id'] ?? item.id;
    final user = Uri.encodeComponent(credentials.username);
    final pass = Uri.encodeComponent(credentials.password);
    return '$root/$path/$user/$pass/$id.$ext';
  }

  void close() => _http.close();
}
