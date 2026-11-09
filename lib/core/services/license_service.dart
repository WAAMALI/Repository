import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// TVEXP subscription client. The server remains the source of truth.
class LicenseService {
  LicenseService._();
  static final instance = LicenseService._();

  static const String _baseUrl =
      'https://tvexp-licensing-api.waamali11286.workers.dev';
  static const String _codeKey = 'tvexp.license.code.v1';
  static const String _deviceKey = 'tvexp.license.device_id.v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final http.Client _client = http.Client();

  String? _activeCode;
  String? _deviceId;

  Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    var id = await _storage.read(key: _deviceKey);
    if (id == null || id.length < 32) {
      final random = Random.secure();
      id = List<int>.generate(32, (_) => random.nextInt(256))
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      await _storage.write(key: _deviceKey, value: id);
    }

    _deviceId = id;
    return id;
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/$endpoint'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
    } catch (_) {
      data = <String, dynamic>{};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LicenseException(
        (data['error'] ?? 'تعذر التحقق من الاشتراك').toString(),
      );
    }
    return data;
  }

  /// Activates the supplied 12-digit code on this installation.
  Future<void> activate(String code) async {
    final normalized = code.trim();
    if (!RegExp(r'^\d{12}$').hasMatch(normalized)) {
      throw LicenseException('كود الاشتراك يجب أن يتكون من 12 رقمًا.');
    }

    final deviceId = await _getDeviceId();
    final result = await _post('activate', {
      'code': normalized,
      'deviceId': deviceId,
    });

    if (result['success'] != true) {
      throw LicenseException(
        (result['error'] ?? 'تعذر تفعيل الاشتراك').toString(),
      );
    }

    await _storage.write(key: _codeKey, value: normalized);
    _activeCode = normalized;
  }

  /// Validates the saved code against the server. Fails closed on network errors.
  Future<bool> restoreAndValidate() async {
    final code = await _storage.read(key: _codeKey);
    if (code == null || !RegExp(r'^\d{12}$').hasMatch(code)) {
      _activeCode = null;
      return false;
    }

    _activeCode = code;
    try {
      await validate();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Call before every protected action, not just at app startup.
  Future<void> ensureValid() async {
    if (_activeCode == null) {
      _activeCode = await _storage.read(key: _codeKey);
    }
    if (_activeCode == null) {
      throw LicenseException('أدخل كود الاشتراك أولاً.');
    }

    // Refresh validation on every protected action. No offline bypass.
    await validate();
  }

  Future<Map<String, dynamic>> validate() async {
    final code = _activeCode ?? await _storage.read(key: _codeKey);
    if (code == null) {
      throw LicenseException('لا يوجد كود اشتراك محفوظ.');
    }

    final deviceId = await _getDeviceId();
    final result = await _post('validate', {
      'code': code,
      'deviceId': deviceId,
    });

    if (result['valid'] != true) {
      throw LicenseException(
        (result['error'] ?? 'الاشتراك غير صالح').toString(),
      );
    }

    return result;
  }

  Future<String?> savedCode() => _storage.read(key: _codeKey);

  Future<void> clearSavedCode() async {
    await _storage.delete(key: _codeKey);
    _activeCode = null;
  }
}

class LicenseException implements Exception {
  const LicenseException(this.message);
  final String message;

  @override
  String toString() => message;
}
