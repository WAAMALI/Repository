import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static final instance = AppDatabase._();
  Database? _db;

  Future<void> initialize() async {
    if (_db != null) return;
    final root = await getDatabasesPath();
    _db = await openDatabase(p.join(root, 'tvexp_iptv.db'), version: 4, onCreate: (db, version) async {
      await db.execute('CREATE TABLE favorites (media_id TEXT PRIMARY KEY, name TEXT NOT NULL, section TEXT NOT NULL, image TEXT, created_at INTEGER NOT NULL)');
      await db.execute('CREATE TABLE watch_history (media_id TEXT PRIMARY KEY, name TEXT NOT NULL, section TEXT NOT NULL, image TEXT, position_ms INTEGER NOT NULL DEFAULT 0, duration_ms INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)');
      await db.execute('CREATE TABLE offline_files (media_id TEXT PRIMARY KEY, name TEXT NOT NULL, section TEXT NOT NULL, file_path TEXT NOT NULL, file_size INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)');
      await db.execute('CREATE TABLE categories_cache (section TEXT NOT NULL, category_id TEXT NOT NULL, name TEXT NOT NULL, PRIMARY KEY(section, category_id))');
      await db.execute('CREATE TABLE playlist_cache (profile_id TEXT NOT NULL, item_id TEXT NOT NULL, section TEXT NOT NULL, name TEXT NOT NULL, image TEXT, stream_url TEXT, category_id TEXT, raw_json TEXT, updated_at INTEGER NOT NULL, PRIMARY KEY(profile_id,item_id,section))');
      await db.execute('CREATE INDEX idx_playlist_section ON playlist_cache(profile_id,section)');
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute('CREATE TABLE playlist_cache (profile_id TEXT NOT NULL, item_id TEXT NOT NULL, section TEXT NOT NULL, name TEXT NOT NULL, image TEXT, stream_url TEXT, category_id TEXT, raw_json TEXT, updated_at INTEGER NOT NULL, PRIMARY KEY(profile_id,item_id,section))');
        await db.execute('CREATE INDEX idx_playlist_section ON playlist_cache(profile_id,section)');
      }
      if (oldVersion < 3) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_history_updated ON watch_history(updated_at DESC)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_favorites_created ON favorites(created_at DESC)');
      }
      if (oldVersion < 4) {
        await db.execute('CREATE TABLE offline_files (media_id TEXT PRIMARY KEY, name TEXT NOT NULL, section TEXT NOT NULL, file_path TEXT NOT NULL, file_size INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)');
        await db.execute('CREATE INDEX idx_offline_created ON offline_files(created_at DESC)');
      }
    });
  }

  Database get db {
    final value = _db;
    if (value == null) throw StateError('Database is not initialized');
    return value;
  }

  Future<void> setFavorite({required String id, required String name, required String section, String? image, required bool favorite}) async {
    if (favorite) {
      await db.insert('favorites', {'media_id': id, 'name': name, 'section': section, 'image': image, 'created_at': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await db.delete('favorites', where: 'media_id = ?', whereArgs: [id]);
    }
  }

  Future<List<Map<String, Object?>>> favorites() => db.query('favorites', orderBy: 'created_at DESC');

  Future<void> recordProgress({
    required String id,
    required String name,
    required String section,
    String? image,
    required int positionMs,
    required int durationMs,
  }) async {
    if (id.trim().isEmpty) return;
    await db.insert('watch_history', {
      'media_id': id,
      'name': name,
      'section': section,
      'image': image,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> history({int limit = 100}) =>
      db.query('watch_history', orderBy: 'updated_at DESC', limit: limit);

  Future<Map<String, Object?>?> historyItem(String id) async {
    final rows = await db.query('watch_history',
      where: 'media_id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> removeHistory(String id) =>
      db.delete('watch_history', where: 'media_id = ?', whereArgs: [id]);

  Future<void> clearHistory() => db.delete('watch_history');

  Future<bool> isFavorite(String id) async {
    final rows = await db.query('favorites', columns: ['media_id'],
      where: 'media_id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> clearFavorites() => db.delete('favorites');

  Future<void> registerOfflineFile({
    required String id, required String name, required String section,
    required String filePath, required int fileSize,
  }) async {
    await db.insert('offline_files', {
      'media_id': id, 'name': name, 'section': section,
      'file_path': filePath, 'file_size': fileSize,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> offlineFiles() =>
      db.query('offline_files', orderBy: 'created_at DESC');

  Future<void> removeOfflineFile(String id) =>
      db.delete('offline_files', where: 'media_id = ?', whereArgs: [id]);

  Future<int> offlineStorageBytes() async {
    final rows = await db.rawQuery('SELECT COALESCE(SUM(file_size), 0) AS total FROM offline_files');
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }
}
