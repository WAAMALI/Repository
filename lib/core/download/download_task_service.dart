import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../services/download_bridge.dart';
import '../services/app_database.dart';
import 'range_download_engine.dart';

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.connections,
    this.state = DownloadState.probing,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.localPath,
    this.priority = 0,
    this.createdAt,
    this.headers = const {},
  });
  final String id, url, fileName;
  final int connections;
  DownloadState state;
  int receivedBytes, totalBytes;
  String? error, localPath;
  int priority;
  final int? createdAt;
  final Map<String, String> headers;
  double get progress => totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0).toDouble() : 0.0;
}

class DownloadTaskService {
  DownloadTaskService._();
  static final instance = DownloadTaskService._();
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, RangeDownloadEngine> _engines = {};
  final Set<String> _pauseRequested = {};
  final Set<String> _running = {};
  int _maxConcurrent = 2;
  bool _schedulerBusy = false;
  bool _restored = false;
  Future<void>? _restoreFuture;
  Future<void> _persistQueue = Future<void>.value();
  final _changes = StreamController<List<DownloadTask>>.broadcast();
  Stream<List<DownloadTask>> get changes => _changes.stream;
  List<DownloadTask> get tasks => List.unmodifiable(_tasks.values.toList());

  void _emit() {
    _changes.add(tasks);
    _persist();
  }

  Future<File> get _stateFile async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory(p.join(dir.path, 'tvexp_downloads'));
    await folder.create(recursive: true);
    return File(p.join(folder.path, 'tasks.json'));
  }

  Future<void> _persist() {
    // Capture an immutable snapshot now, then serialize writes to avoid racing
    // progress callbacks and leaving a partially-written tasks.json file.
    final data = _tasks.values.map((t) => {
      'id': t.id, 'url': t.url, 'fileName': t.fileName,
      'connections': t.connections, 'state': t.state.name,
      'receivedBytes': t.receivedBytes, 'totalBytes': t.totalBytes,
      'error': t.error, 'localPath': t.localPath,
      'priority': t.priority, 'createdAt': t.createdAt,
      'headers': t.headers,
    }).toList();
    _persistQueue = _persistQueue.then((_) async {
      try {
        final file = await _stateFile;
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(jsonEncode(data), flush: true);
        if (await file.exists()) await file.delete();
        await temp.rename(file.path);
      } catch (_) {
        // Persistence failure must not crash an active download.
      }
    });
    return _persistQueue;
  }

  Future<void> restore() {
    return _restoreFuture ??= _restoreInternal();
  }

  Future<void> _restoreInternal() async {
    if (_restored) return;
    try {
      final file = await _stateFile;
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString());
        if (raw is List) {
          for (final item in raw.whereType<Map>()) {
            final stateName = item['state']?.toString() ?? 'paused';
            var previous = DownloadState.paused;
            for (final candidate in DownloadState.values) {
              if (candidate.name == stateName) { previous = candidate; break; }
            }
            final state = previous == DownloadState.downloading || previous == DownloadState.probing
                ? DownloadState.paused : previous;
            final task = DownloadTask(
              id: item['id'].toString(),
              url: item['url'].toString(),
              fileName: item['fileName'].toString(),
              connections: (item['connections'] as num?)?.toInt() ?? 4,
              state: state,
              receivedBytes: (item['receivedBytes'] as num?)?.toInt() ?? 0,
              totalBytes: (item['totalBytes'] as num?)?.toInt() ?? 0,
              error: state == DownloadState.paused ? 'أُعيد تحميل المهمة بعد إغلاق التطبيق' : item['error']?.toString(),
              localPath: item['localPath']?.toString(),
              priority: (item['priority'] as num?)?.toInt() ?? 0,
              createdAt: (item['createdAt'] as num?)?.toInt(),
              headers: item['headers'] is Map
                  ? Map<String, String>.from((item['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
                  : const {},
            );
            _tasks[task.id] = task;
          }
        }
      }
    } catch (_) {
      // Ignore a corrupt task index; segment manifests remain available for manual re-add.
    }
    _restored = true;
    _emit();
    // Tasks saved in the queued state are safe to schedule automatically.
    // In-flight tasks are deliberately restored as paused and need user action.
    unawaited(_schedule());
  }

  Future<String> add({
    required String url,
    required String fileName,
    int connections = 4,
    int priority = 0,
    Map<String, String> headers = const {},
  }) async {
    await restore();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasAuthority || !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('رابط التحميل يجب أن يبدأ بـ HTTP أو HTTPS');
    }
    final safe = p.basename(fileName).trim();
    if (safe.isEmpty || safe == '.' || safe == '..') {
      throw const FormatException('اسم الملف غير صالح');
    }
    DownloadTask? duplicate;
    for (final existing in _tasks.values) {
      if (existing.url == uri.toString() &&
          existing.fileName.toLowerCase() == safe.toLowerCase() &&
          existing.state != DownloadState.failed) {
        duplicate = existing;
        break;
      }
    }
    if (duplicate != null) return duplicate.id;
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final task = DownloadTask(id: id, url: uri.toString(), fileName: safe,
      connections: connections.clamp(1, 8).toInt(), state: DownloadState.queued,
      priority: priority.clamp(0, 5).toInt(), createdAt: DateTime.now().millisecondsSinceEpoch,
      headers: Map.unmodifiable(headers));
    _tasks[id] = task;
    try { await DownloadBridge.instance.startInternalForeground(); } catch (_) {}
    _emit();
    unawaited(_schedule());
    return id;
  }

  Future<void> setMaxConcurrent(int value) async {
    _maxConcurrent = value.clamp(1, 4).toInt();
    await _persist();
    await _schedule();
  }

  Future<void> setPriority(String id, int priority) async {
    final task = _tasks[id];
    if (task == null || task.state == DownloadState.downloading ||
        task.state == DownloadState.probing) return;
    task.priority = priority.clamp(0, 5).toInt();
    _emit();
    await _schedule();
  }

  Future<void> _schedule() async {
    if (_schedulerBusy) return;
    _schedulerBusy = true;
    try {
      while (_running.length < _maxConcurrent) {
        final waiting = _tasks.values.where((t) =>
          t.state == DownloadState.queued).toList()
          ..sort((a,b) {
            final byPriority = b.priority.compareTo(a.priority);
            if (byPriority != 0) return byPriority;
            return (a.createdAt ?? 0).compareTo(b.createdAt ?? 0);
          });
        if (waiting.isEmpty) break;
        final task = waiting.first;
        _running.add(task.id);
        unawaited(_run(task, task.headers));
      }
    } finally {
      _schedulerBusy = false;
    }
  }

  Future<void> _run(DownloadTask task, Map<String, String> headers) async {
    final engine = RangeDownloadEngine(maxConnections: task.connections);
    _engines[task.id] = engine;
    task.state = DownloadState.probing;
    task.error = null;
    _emit();
    try {
      final file = await engine.download(
        uri: Uri.parse(task.url),
        fileName: task.fileName,
        headers: headers,
        onProgress: (progress) {
          task.state = progress.state;
          task.receivedBytes = progress.receivedBytes;
          task.totalBytes = progress.totalBytes;
          task.error = progress.error;
          _emit();
        },
      );
      task.localPath = file.path;
      task.state = DownloadState.completed;
      await AppDatabase.instance.registerOfflineFile(
        id: task.id,
        name: task.fileName,
        section: 'download',
        filePath: file.path,
        fileSize: await file.length(),
      );
    } catch (e) {
      task.error = e.toString();
      task.state = _pauseRequested.remove(task.id)
        ? DownloadState.paused : DownloadState.failed;
    } finally {
      _engines.remove(task.id);
      _running.remove(task.id);
      _emit();
      final hasActive = _tasks.values.any((t) =>
        t.state == DownloadState.probing || t.state == DownloadState.downloading);
      if (!hasActive) {
        try { await DownloadBridge.instance.stopInternalForeground(); } catch (_) {}
      }
      unawaited(_schedule());
    }
  }

  void pause(String id) {
    final task = _tasks[id];
    if (task == null) return;
    _pauseRequested.add(id);
    task.state = DownloadState.paused;
    _emit();
    _engines[id]?.pause();
  }

  Future<void> resume(String id) async {
    final task = _tasks[id];
    if (task == null || (task.state != DownloadState.paused && task.state != DownloadState.failed)) return;
    _pauseRequested.remove(id);
    task.state = DownloadState.queued;
    task.error = null;
    _emit();
    await _schedule();
  }

  Future<void> remove(String id) async {
    _engines[id]?.pause();
    _engines.remove(id);
    _tasks.remove(id);
    _emit();
    final hasActive = _tasks.values.any((t) =>
      t.state == DownloadState.probing || t.state == DownloadState.downloading);
    if (!hasActive) {
      try { await DownloadBridge.instance.stopInternalForeground(); } catch (_) {}
    }
  }

  Future<void> dispose() async => _changes.close();
}
