import 'package:http/http.dart' as http;
import '../models/iptv_models.dart';
import 'm3u_parser.dart';

class PlaylistService {
  PlaylistService({http.Client? client}):_client=client??http.Client();
  final http.Client _client;
  Future<List<MediaItem>> loadM3u(String source,{String? username,String? password}) async {
    var uri=Uri.parse(source.trim());
    if(username!=null && password!=null && uri.queryParameters['username']==null){
      uri=uri.replace(queryParameters:{...uri.queryParameters,'username':username,'password':password});
    }
    final response=await _client.get(uri,headers:const {'Accept':'audio/x-mpegurl, application/vnd.apple.mpegurl, */*','User-Agent':'TVEXP-IPTV-Android/2.2'}).timeout(const Duration(seconds:40));
    if(response.statusCode<200 || response.statusCode>=300) throw Exception('تعذر تحميل القائمة: HTTP ${response.statusCode}');
    final items=M3uParser.parse(response.body);
    if(items.isEmpty) throw const FormatException('القائمة فارغة أو لا تحتوي على روابط M3U صالحة');
    return items;
  }
  void close()=>_client.close();
}
