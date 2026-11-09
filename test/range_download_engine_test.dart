import 'package:flutter_test/flutter_test.dart';
import 'package:tvexp_iptv/core/download/range_download_engine.dart';

void main() {
  test('accepts supported connection counts', () {
    expect(() => RangeDownloadEngine(maxConnections: 1), returnsNormally);
    expect(() => RangeDownloadEngine(maxConnections: 4), returnsNormally);
    expect(() => RangeDownloadEngine(maxConnections: 8), returnsNormally);
  });

  test('rejects excessive connection count', () {
    expect(() => RangeDownloadEngine(maxConnections: 9), throwsAssertionError);
  });

  test('reports bounded progress', () {
    const progress = DownloadProgress(
      receivedBytes: 50, totalBytes: 100, state: DownloadState.downloading);
    expect(progress.fraction, 0.5);
  });
}
