/// Authenticated HTTP client for the YXZ production API.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'installation_auth.dart';

/// Thin REST client with bearer + one refresh retry.
class YxzApiClient {
  /// Creates the client.
  YxzApiClient({
    required this.auth,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Installation auth helper (owns base URL).
  final InstallationAuthService auth;

  final http.Client _client;

  /// GET JSON.
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    return _requestJson('GET', path, query: query);
  }

  /// POST JSON body.
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _requestJson('POST', path, body: body);
  }

  Future<Map<String, dynamic>> _requestJson(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool didRefresh = false,
  }) async {
    await auth.ensureRegistered();
    final String? token = await auth.accessToken();
    if (token == null) {
      throw ApiException(
        code: 'AUTH_INVALID',
        message: 'No access token',
        kind: ApiFailureKind.auth,
        statusCode: 401,
      );
    }
    final Uri uri = Uri.parse(_join(auth.baseUrl, path)).replace(
      queryParameters: query,
    );
    late final http.Response res;
    try {
      final Map<String, String> headers = <String, String>{
        'authorization': 'Bearer $token',
        'accept': 'application/json',
        if (body != null) 'content-type': 'application/json',
      };
      res = await (method == 'POST'
              ? _client.post(
                  uri,
                  headers: headers,
                  body: body == null ? null : jsonEncode(body),
                )
              : _client.get(uri, headers: headers))
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw ApiException(
        code: 'PLAYBACK_NETWORK_ERROR',
        message: 'Request timed out',
        kind: ApiFailureKind.transport,
        retryable: true,
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        code: 'PLAYBACK_NETWORK_ERROR',
        message: e.message,
        kind: ApiFailureKind.transport,
        retryable: true,
      );
    }

    if (res.statusCode == 401 && !didRefresh) {
      await auth.refresh();
      return _requestJson(
        method,
        path,
        query: query,
        body: body,
        didRefresh: true,
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _parseError(res);
    }
    if (res.body.isEmpty) {
      return <String, dynamic>{};
    }
    final Object? decoded = jsonDecode(res.body);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw ApiException(
      code: 'VALIDATION_ERROR',
      message: 'Expected JSON object',
      kind: ApiFailureKind.client,
      statusCode: res.statusCode,
    );
  }

  static String _join(String base, String path) {
    final String b =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final String p = path.startsWith('/') ? path : '/$path';
    return '$b$p';
  }

  static ApiException _parseError(http.Response res) {
    String code = 'INTERNAL_ERROR';
    String message = res.reasonPhrase ?? 'Request failed';
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
      // ignore
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
