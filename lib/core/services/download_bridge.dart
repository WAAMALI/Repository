import 'package:flutter/services.dart';

class NativeDownload {
  const NativeDownload({
    required this.id,
    required this.status,
    required this.downloaded,
    required this.total,
    this.title,
    this.reason = 0,
    this.localUri,
    this.contentUri,
    this.url,
  });

  final int id;
  final int status;
  final int reason;
  final int downloaded;
  final int total;
  final String? title;
  final String? localUri;
  final String? contentUri;
  final String? url;

  double get progress => total > 0 ? (downloaded / total).clamp(0.0, 1.0).toDouble() : 0.0;
  bool get isComplete => status == 8; // DownloadManager.STATUS_SUCCESSFUL
  bool get isFailed => status == 16; // DownloadManager.STATUS_FAILED
  bool get isRunning => status == 2; // DownloadManager.STATUS_RUNNING
  bool get isPending => status == 1; // DownloadManager.STATUS_PENDING
  bool get isPaused => status == 4; // DownloadManager.STATUS_PAUSED

  factory NativeDownload.fromMap(Map<dynamic, dynamic> map) => NativeDownload(
    id: (map['id'] as num).toInt(),
    title: map['title'] as String?,
    status: (map['status'] as num).toInt(),
    reason: (map['reason'] as num?)?.toInt() ?? 0,
    downloaded: (map['downloaded'] as num?)?.toInt() ?? 0,
    total: (map['total'] as num?)?.toInt() ?? 0,
    localUri: map['localUri'] as String?,
    contentUri: map['contentUri'] as String?,
    url: map['uri'] as String?,
  );
}

class DownloadBridge {
  DownloadBridge._();
  static final instance = DownloadBridge._();
  static const _channel = MethodChannel('com.tvexp.iptv/downloads');

  Future<void> startInternalForeground() async {
    await _channel.invokeMethod<bool>('startInternalForeground');
  }

  Future<void> stopInternalForeground() async {
    await _channel.invokeMethod<bool>('stopInternalForeground');
  }

  Future<int?> enqueue({
    required String url,
    required String fileName,
    String? title,
  }) async => _channel.invokeMethod<int>('enqueue', {
    'url': url, 'fileName': fileName, 'title': title ?? fileName,
  });

  Future<List<NativeDownload>> queryAll() async {
    final result = await _channel.invokeMethod<List<dynamic>>('queryAll');
    return (result ?? const []).map((e) =>
      NativeDownload.fromMap(Map<dynamic, dynamic>.from(e as Map))).toList();
  }

  Future<void> remove(int id) async {
    await _channel.invokeMethod<int>('remove', {'id': id});
  }

  Future<void> shareToExternalManager({
    required String url,
    required String fileName,
  }) async {
    await _channel.invokeMethod<void>('shareExternal', {
      'url': url, 'fileName': fileName,
    });
  }
}
