import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum DownloadState { queued, probing, downloading, paused, completed, failed }

class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.state,
    this.error,
  });
  final int receivedBytes;
  final int totalBytes;
  final DownloadState state;
  final String? error;
  double get fraction => totalBytes > 0
      ? (receivedBytes / totalBytes).clamp(0.0, 1.0).toDouble()
      : 0;
}

class RangeDownloadEngine {
  RangeDownloadEngine({this.maxConnections = 4})
      : assert(maxConnections >= 1 && maxConnections <= 8);

  final int maxConnections;
  HttpClient? _client;
  bool _pauseRequested = false;

  Future<File> download({
    required Uri uri,
    required String fileName,
    required void Function(DownloadProgress) onProgress,
    Map<String, String> headers = const {},
  }) async {
    if (!const {'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('Only HTTP and HTTPS URLs are supported');
    }
    _pauseRequested = false;
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 45)
      ..maxConnectionsPerHost = maxConnections;

    final root = await getApplicationSupportDirectory();
    final safeName = p.basename(fileName).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final jobKey = _stableKey(uri.toString());
    final jobDir = Directory(p.join(root.path, 'tvexp_downloads', '${safeName}_$jobKey'));
    await jobDir.create(recursive: true);
    final finalFile = File(p.join(jobDir.path, safeName));
    final manifest = File(p.join(jobDir.path, 'manifest.json'));

    try {
      final probe = await _probe(uri, headers);
      final total = probe.totalBytes;
      if (total <= 0) throw HttpException('Server did not provide a valid content length');

      final old = await _readManifest(manifest);
      final count = probe.supportsRanges ? maxConnections.clamp(1, total).toInt() : 1;
      final segments = _makeSegments(total, count);
      final oldSegments = old?['segments'];
      final sameSegments = oldSegments is List &&
          oldSegments.length == segments.length &&
          List.generate(segments.length, (i) {
            final item = oldSegments[i];
            return item is Map && item['start'] == segments[i].start &&
                item['end'] == segments[i].end;
          }).every((matches) => matches);
      final canResume = old?['url'] == uri.toString() &&
          old?['totalBytes'] == total &&
          old?['supportsRanges'] == probe.supportsRanges &&
          sameSegments;
      if (!canResume) {
        for (final f in jobDir.listSync().whereType<File>()) {
          if (f.path.endsWith('.part')) await f.delete();
        }
      }
      await manifest.writeAsString(jsonEncode({
        'url': uri.toString(),
        'totalBytes': total,
        'supportsRanges': probe.supportsRanges,
        'segments': segments.map((e) => {'start': e.start, 'end': e.end}).toList(),
      }));

      onProgress(DownloadProgress(receivedBytes: _sumParts(jobDir, segments),
          totalBytes: total, state: DownloadState.downloading));

      await Future.wait(List.generate(segments.length, (i) async {
        await _downloadSegment(
          uri: uri, headers: headers, directory: jobDir,
          segment: segments[i], index: i, useRange: probe.supportsRanges,
          onBytes: (_) => onProgress(DownloadProgress(
            receivedBytes: _sumParts(jobDir, segments),
            totalBytes: total, state: _pauseRequested
              ? DownloadState.paused : DownloadState.downloading)),
        );
      }));

      if (_pauseRequested) {
        onProgress(DownloadProgress(receivedBytes: _sumParts(jobDir, segments),
          totalBytes: total, state: DownloadState.paused));
        throw const _PausedException();
      }

      final output = await finalFile.open(mode: FileMode.write);
      try {
        for (var i = 0; i < segments.length; i++) {
          final part = File(p.join(jobDir.path, 'segment_$i.part'));
          await output.writeFrom(await part.readAsBytes());
        }
      } finally {
        await output.close();
      }
      onProgress(DownloadProgress(receivedBytes: total,
          totalBytes: total, state: DownloadState.completed));
      return finalFile;
    } on _PausedException {
      rethrow;
    } catch (e) {
      onProgress(DownloadProgress(receivedBytes: 0, totalBytes: 0,
          state: DownloadState.failed, error: e.toString()));
      rethrow;
    } finally {
      _client?.close(force: true);
      _client = null;
    }
  }

  void pause() {
    _pauseRequested = true;
    _client?.close(force: true);
  }

  Future<_Probe> _probe(Uri uri, Map<String, String> headers) async {
    final client = _client!;
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final response = await request.close();
    final contentRange = response.headers.value('content-range');
    final length = response.headers.contentLength;
    final rangeMatch = contentRange == null
        ? null : RegExp(r'bytes\s+\d+-\d+/(\d+)', caseSensitive: false).firstMatch(contentRange);
    final total = int.tryParse(rangeMatch?.group(1) ?? '') ?? length;
    final supportsRanges = response.statusCode == HttpStatus.partialContent &&
        rangeMatch != null && total > 0;
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw HttpException('Probe failed: HTTP ${response.statusCode}', uri: uri);
    }
    // A server may ignore Range and return HTTP 200 with the entire movie.
    // Cancel the probe stream immediately instead of downloading it just to
    // discard the bytes before starting the real transfer.
    final subscription = response.listen((_) {});
    await subscription.cancel();
    return _Probe(total, supportsRanges);
  }

  Future<void> _downloadSegment({
    required Uri uri,
    required Map<String, String> headers,
    required Directory directory,
    required _Segment segment,
    required int index,
    required bool useRange,
    required void Function(int) onBytes,
  }) async {
    const maxAttempts = 4;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_pauseRequested) throw const _PausedException();

      try {
        await _downloadSegmentOnce(
          uri: uri,
          headers: headers,
          directory: directory,
          segment: segment,
          index: index,
          useRange: useRange,
          onBytes: onBytes,
        );
        return;
      } catch (error) {
        if (error is _PausedException) rethrow;
        lastError = error;

        if (attempt == maxAttempts) break;

        // Keep valid partial bytes for Range servers and retry transient
        // connection/server failures with exponential backoff.
        final delaySeconds = attempt * 2;
        await Future<void>.delayed(Duration(seconds: delaySeconds));
      }
    }

    throw HttpException(
      'Segment $index failed after $maxAttempts attempts: $lastError',
      uri: uri,
    );
  }

  Future<void> _downloadSegmentOnce({
    required Uri uri,
    required Map<String, String> headers,
    required Directory directory,
    required _Segment segment,
    required int index,
    required bool useRange,
    required void Function(int) onBytes,
  }) async {
    final part = File(p.join(directory.path, 'segment_$index.part'));
    var existing = await part.exists() ? await part.length() : 0;
    final expected = segment.end - segment.start + 1;
    // A non-range server must restart from byte zero; appending would corrupt the file.
    if (!useRange && existing > 0) {
      await part.delete();
      existing = 0;
    }
    if (existing > expected) {
      await part.delete();
      existing = 0;
    }
    if (existing == expected) return;

    final start = segment.start + existing;
    final client = _client!;
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    if (useRange) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-${segment.end}');
    final response = await request.close().timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        request.abort();
        throw TimeoutException('Timed out waiting for download response');
      },
    );
    if (useRange && response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw HttpException('Server stopped honoring byte ranges');
    }
    if (useRange) {
      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      final match = contentRange == null
          ? null
          : RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$', caseSensitive: false)
              .firstMatch(contentRange.trim());
      final reportedStart = int.tryParse(match?.group(1) ?? '');
      final reportedEnd = int.tryParse(match?.group(2) ?? '');
      if (reportedStart != start || reportedEnd != segment.end) {
        await response.drain<void>();
        throw HttpException('Invalid Content-Range for segment $index: $contentRange');
      }
    }
    if (!useRange && response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('Download failed: HTTP ${response.statusCode}');
    }

    final sink = part.openWrite(mode: FileMode.append);
    try {
      await for (final chunk in response.timeout(
        const Duration(seconds: 60),
        onTimeout: (sink) {
          sink.addError(TimeoutException('Download stalled for 60 seconds'));
          sink.close();
        },
      )) {
        if (_pauseRequested) throw const _PausedException();
        sink.add(chunk);
        onBytes(chunk.length);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    final actual = await part.length();
    if (actual != expected) {
      throw HttpException('Incomplete segment $index: $actual/$expected bytes');
    }
  }

  List<_Segment> _makeSegments(int total, int count) {
    final result = <_Segment>[];
    final chunk = (total / count).ceil();
    for (var start = 0; start < total; start += chunk) {
      final end = (start + chunk - 1).clamp(0, total - 1).toInt();
      result.add(_Segment(start, end));
    }
    return result;
  }

  int _sumParts(Directory dir, List<_Segment> segments) {
    var sum = 0;
    for (var i = 0; i < segments.length; i++) {
      final file = File(p.join(dir.path, 'segment_$i.part'));
      if (file.existsSync()) sum += file.lengthSync();
    }
    return sum;
  }

  String _stableKey(String value) {
    // Stable FNV-1a key so different URLs with the same filename never share parts.
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<Map<String, dynamic>?> _readManifest(File file) async {
    if (!await file.exists()) return null;
    try { return jsonDecode(await file.readAsString()) as Map<String, dynamic>; }
    catch (_) { return null; }
  }
}

class _Probe {
  const _Probe(this.totalBytes, this.supportsRanges);
  final int totalBytes;
  final bool supportsRanges;
}

class _Segment {
  const _Segment(this.start, this.end);
  final int start;
  final int end;
}

class _PausedException implements Exception {
  const _PausedException();
}
