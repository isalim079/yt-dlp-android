/// Install JWT registration + secure storage.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Credentials returned by `POST /api/v1/installations`.
class InstallationCredentials {
  /// Creates credentials.
  const InstallationCredentials({
    required this.installationId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  /// Server installation id.
  final String installationId;

  /// Short-lived access JWT.
  final String accessToken;

  /// Rotating refresh credential.
  final String refreshToken;

  /// Access TTL seconds.
  final int expiresIn;

  /// Parses JSON body.
  factory InstallationCredentials.fromJson(Map<String, dynamic> json) {
    return InstallationCredentials(
      installationId: json['installationId'] as String,
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 900,
    );
  }
}

/// Registers installations and refreshes JWTs.
class InstallationAuthService {
  /// Creates the auth service.
  InstallationAuthService({
    required this.baseUrl,
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  /// API origin, e.g. `http://10.0.2.2:8080`.
  String baseUrl;

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const String _kInstallId = 'yxz_installation_id';
  static const String _kAccess = 'yxz_access_token';
  static const String _kRefresh = 'yxz_refresh_token';

  /// Ensures tokens exist; registers when missing.
  Future<InstallationCredentials> ensureRegistered() async {
    final String? access = await _storage.read(key: _kAccess);
    final String? refresh = await _storage.read(key: _kRefresh);
    final String? id = await _storage.read(key: _kInstallId);
    if (access != null &&
        refresh != null &&
        id != null &&
        access.isNotEmpty) {
      return InstallationCredentials(
        installationId: id,
        accessToken: access,
        refreshToken: refresh,
        expiresIn: 900,
      );
    }
    return register();
  }

  /// `POST /api/v1/installations`.
  Future<InstallationCredentials> register() async {
    final Uri uri = Uri.parse(_join(baseUrl, '/api/v1/installations'));
    final http.Response res = await _client
        .post(uri, headers: <String, String>{'content-type': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _fromResponse(res);
    }
    final Map<String, dynamic> body =
        jsonDecode(res.body) as Map<String, dynamic>;
    final InstallationCredentials creds =
        InstallationCredentials.fromJson(body);
    await _persist(creds);
    return creds;
  }

  /// `POST /api/v1/auth/refresh`.
  Future<InstallationCredentials> refresh() async {
    final String? id = await _storage.read(key: _kInstallId);
    final String? refresh = await _storage.read(key: _kRefresh);
    if (id == null || refresh == null) {
      return register();
    }
    final Uri uri = Uri.parse(_join(baseUrl, '/api/v1/auth/refresh'));
    final http.Response res = await _client
        .post(
          uri,
          headers: <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, String>{
            'installationId': id,
            'refreshToken': refresh,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _fromResponse(res);
    }
    final InstallationCredentials creds = InstallationCredentials.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
    await _persist(creds);
    return creds;
  }

  /// Current access token or null.
  Future<String?> accessToken() => _storage.read(key: _kAccess);

  Future<void> _persist(InstallationCredentials creds) async {
    await _storage.write(key: _kInstallId, value: creds.installationId);
    await _storage.write(key: _kAccess, value: creds.accessToken);
    await _storage.write(key: _kRefresh, value: creds.refreshToken);
  }

  static String _join(String base, String path) {
    final String b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$b$path';
  }

  static ApiException _fromResponse(http.Response res) {
    String code = 'INTERNAL_ERROR';
    String message = res.body;
    bool retryable = false;
    try {
      final Object? decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is Map) {
        final Map<String, dynamic> err =
            Map<String, dynamic>.from(decoded['error'] as Map);
        code = err['code']?.toString() ?? code;
        message = err['message']?.toString() ?? message;
        retryable = err['retryable'] == true;
      }
    } on Object {
      // keep defaults
    }
    return ApiException(
      code: code,
      message: message,
      kind: classifyApiFailure(statusCode: res.statusCode, code: code),
      statusCode: res.statusCode,
      retryable: retryable,
    );
  }
}
