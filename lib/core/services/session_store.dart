import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/iptv_models.dart';

class SessionStore {
  SessionStore._();
  static final instance = SessionStore._();
  static const _key = 'tvexp.profiles.v2';
  static const _activeKey = 'tvexp.active_profile.v2';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<List<PlaylistProfile>> profiles() async {
    final raw=await _storage.read(key:_key);
    if(raw==null || raw.isEmpty) return [];
    try { return (jsonDecode(raw) as List).whereType<Map>().map((e)=>PlaylistProfile.fromJson(Map<String,dynamic>.from(e))).toList(); }
    catch (_) { return []; }
  }
  Future<String?> activeProfileId()=>_storage.read(key:_activeKey);
  Future<PlaylistProfile?> activeProfile() async {
    final id=await activeProfileId(); final all=await profiles();
    for(final p in all){if(p.id==id)return p;} return null;
  }
  Future<void> saveProfile(PlaylistProfile profile,{bool activate=true}) async {
    final all=await profiles(); final index=all.indexWhere((p)=>p.id==profile.id);
    if(index<0) all.add(profile); else all[index]=profile;
    await _storage.write(key:_key,value:jsonEncode(all.map((e)=>e.toJson()).toList()));
    if(activate) await _storage.write(key:_activeKey,value:profile.id);
  }
  Future<void> activate(String id) async {
    if(!(await profiles()).any((p)=>p.id==id)) throw StateError('الاشتراك غير موجود');
    await _storage.write(key:_activeKey,value:id);
  }
  Future<void> deleteProfile(String id) async {
    final all=await profiles(); all.removeWhere((p)=>p.id==id);
    await _storage.write(key:_key,value:jsonEncode(all.map((e)=>e.toJson()).toList()));
    if(await activeProfileId()==id){ if(all.isEmpty){await _storage.delete(key:_activeKey);} else {await activate(all.first.id);} }
  }
  Future<void> save(XtreamCredentials c) async => saveProfile(PlaylistProfile(id:'${c.normalizedServer}|${c.username}',name:c.username,type:PlaylistType.xtream,source:c.normalizedServer,username:c.username,password:c.password));
  Future<XtreamCredentials?> read() async {
    final p=await activeProfile();
    if(p==null || p.type!=PlaylistType.xtream) return null;
    return XtreamCredentials(server:p.source,username:p.username,password:p.password);
  }
  Future<void> clear() async { final id=await activeProfileId(); if(id!=null) await deleteProfile(id); }
}
