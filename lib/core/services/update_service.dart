import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class TvexpUpdate {
  final String version;
  final int versionCode;
  final String downloadUrl;
  final String releaseTag;
  final String applicationId;

  const TvexpUpdate({
    required this.version,
    required this.versionCode,
    required this.downloadUrl,
    required this.releaseTag,
    required this.applicationId,
  });

  factory TvexpUpdate.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final versionCode = json['versionCode'];
    final downloadUrl = json['downloadUrl'];
    final releaseTag = json['releaseTag'];
    final applicationId = json['applicationId'];

    if (version is! String ||
        versionCode is! num ||
        downloadUrl is! String ||
        releaseTag is! String ||
        applicationId is! String) {
      throw const FormatException('Invalid update manifest fields');
    }

    return TvexpUpdate(
      version: version,
      versionCode: versionCode.toInt(),
      downloadUrl: downloadUrl,
      releaseTag: releaseTag,
      applicationId: applicationId,
    );
  }
}

class UpdateService {
  static String lastCheckMessage = 'لم يبدأ فحص التحديث بعد.';
  static const MethodChannel _channel =
      MethodChannel('com.tvexp.iptv/updates');

  static const String _owner = 'WAAMALI';
  static const String _repo = 'tvexp-releases';

  static String _manifestUrl(String flavor) {
    // Cache-busting query prevents a stale manifest from being reused.
    return 'https://raw.githubusercontent.com/'
        '$_owner/$_repo/main/latest-$flavor.json'
        '?_=${DateTime.now().millisecondsSinceEpoch}';
  }

  static bool _isValidDownloadUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;

    return uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.userInfo.isEmpty &&
        uri.port == 443 &&
        uri.path.startsWith('/$_owner/$_repo/releases/download/');
  }

  static Future<TvexpUpdate?> check() async {
    Map<String, dynamic> config;

    try {
      final rawConfig = await _channel.invokeMethod<dynamic>(
        'getUpdateConfig',
      );

      if (rawConfig is! Map) {
        lastCheckMessage = 'تعذر قراءة إعدادات إصدار التطبيق من Android.';
        debugPrint('[TVEXP UPDATE] Native update config is not a map.');
        return null;
      }

      config = Map<String, dynamic>.from(rawConfig);
    } catch (error, stack) {
      lastCheckMessage = 'تعذر قراءة إصدار التطبيق: $error';
      debugPrint('[TVEXP UPDATE] Cannot read native app config: $error');
      debugPrintStack(stackTrace: stack);
      return null;
    }

    final flavor = config['flavor'] == 'tv' ? 'tv' : 'mobile';
    final expectedApplicationId = flavor == 'tv'
        ? 'com.tvexp.iptv.tv'
        : 'com.tvexp.iptv';

    final currentCodeValue = config['versionCode'];
    final currentNameValue = config['versionName'];
    final currentApplicationId = config['applicationId'];

    if (currentCodeValue is! num ||
        currentNameValue is! String ||
        currentApplicationId is! String) {
      debugPrint('[TVEXP UPDATE] Native app version data is incomplete: $config');
      return null;
    }

    final currentCode = currentCodeValue.toInt();

    debugPrint(
      '[TVEXP UPDATE] Current app: flavor=$flavor, '
      'version=$currentNameValue, code=$currentCode, '
      'applicationId=$currentApplicationId',
    );

    if (currentApplicationId != expectedApplicationId) {
      lastCheckMessage = 'معرّف التطبيق لا يطابق نسخة Mobile/TV.';
      debugPrint('[TVEXP UPDATE] Application ID does not match flavor.');
      return null;
    }

    // Retry transient network/CDN failures instead of silently giving up
    // after the first request.
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await http.get(
          Uri.parse(_manifestUrl(flavor)),
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache, no-store, max-age=0',
            'Pragma': 'no-cache',
          },
        ).timeout(const Duration(seconds: 15));

        debugPrint(
          '[TVEXP UPDATE] Manifest attempt $attempt: '
          'HTTP ${response.statusCode}',
        );

        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Manifest HTTP ${response.statusCode}');
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Manifest root is not a JSON object');
        }

        if (decoded['service'] != flavor ||
            decoded['platform'] != 'android') {
          throw const FormatException('Manifest service/platform mismatch');
        }

        final update = TvexpUpdate.fromJson(decoded);

        if (update.version.isEmpty ||
            update.releaseTag.isEmpty ||
            update.versionCode <= 0 ||
            update.applicationId != expectedApplicationId ||
            !_isValidDownloadUrl(update.downloadUrl)) {
          throw const FormatException('Manifest contains invalid update data');
        }

        debugPrint(
          '[TVEXP UPDATE] Published version: ${update.version}, '
          'code=${update.versionCode}, appId=${update.applicationId}',
        );

        if (update.versionCode <= currentCode) {
          lastCheckMessage = 'لا يوجد تحديث أحدث. المثبت: ${config['versionName']} (Build $currentCode)، المنشور: ${update.version} (Build ${update.versionCode}).';
          debugPrint(
            '[TVEXP UPDATE] No update: published code '
            '${update.versionCode} is not greater than installed code $currentCode. '
            'The next release must use versionCode ${currentCode + 1} or higher.',
          );
          return null;
        }

        lastCheckMessage = 'يتوفر تحديث ${update.version} (Build ${update.versionCode}).';
        debugPrint('[TVEXP UPDATE] Update available: ${update.version}');
        return update;
      } catch (error, stack) {
        lastCheckMessage = 'فشل فحص التحديث (محاولة $attempt): $error';
        debugPrint('[TVEXP UPDATE] Attempt $attempt failed: $error');
        if (attempt == 3) {
          debugPrintStack(stackTrace: stack);
        } else {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }

    return null;
  }

  static Future<void> downloadAndInstall(
    TvexpUpdate update, {
    required void Function(int received, int total) onProgress,
  }) async {
    final client = http.Client();
    File? apkFile;

    try {
      if (!_isValidDownloadUrl(update.downloadUrl)) {
        throw const FormatException('Invalid update download URL');
      }

      if (update.versionCode <= 0 ||
          update.version.isEmpty ||
          update.releaseTag.isEmpty) {
        throw const FormatException('Invalid update information');
      }

      final request = http.Request('GET', Uri.parse(update.downloadUrl))
        ..followRedirects = true
        ..maxRedirects = 5;

      final response = await client.send(request).timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != HttpStatus.ok) {
        await response.stream.listen((_) {}).cancel();
        throw HttpException('Download failed: HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      if (total <= 0) {
        await response.stream.listen((_) {}).cancel();
        throw const HttpException(
          'Update server did not provide a valid file size',
        );
      }

      final directory = await getTemporaryDirectory();
      final updates = Directory('${directory.path}/updates');
      if (!await updates.exists()) {
        await updates.create(recursive: true);
      }

      apkFile = File('${updates.path}/tvexp-update.apk');
      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();
      var received = 0;

      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          if (received > total) {
            throw const FileSystemException(
              'Downloaded APK exceeds expected size',
            );
          }
          sink.add(chunk);
          onProgress(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (received != total ||
          !await apkFile.exists() ||
          await apkFile.length() != total) {
        throw FileSystemException('Downloaded APK size mismatch');
      }

      final result = await _channel.invokeMethod<String>(
        'installApk',
        {'path': apkFile.path},
      );

      if (result != 'installer_opened' &&
          result != 'permission_required') {
        throw PlatformException(code: 'INSTALL_NOT_STARTED');
      }
    } catch (_) {
      if (apkFile != null && await apkFile.exists()) {
        try {
          await apkFile.delete();
        } catch (_) {
          // Ignore cleanup errors.
        }
      }
      rethrow;
    } finally {
      client.close();
    }
  }
}
