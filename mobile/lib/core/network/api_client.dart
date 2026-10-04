import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../config/app_config.dart';
import '../errors/app_exception.dart';

/// Abstraction over the HTTP layer. Repositories depend on this interface so
/// the transport (http, dio, a fake in tests) can change without touching them.
abstract interface class ApiClient {
  Future<dynamic> get(String path, {Map<String, String>? query});
  Future<dynamic> post(String path, {Object? body});
  Future<dynamic> put(String path, {Object? body});
  Future<dynamic> patch(String path, {Object? body});
  Future<dynamic> delete(String path);

  /// Uploads one file as multipart/form-data. [onProgress] receives 0..1 as
  /// request bytes are written to the socket.
  Future<dynamic> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    String field = 'file',
    void Function(double progress)? onProgress,
  });
}

/// MultipartRequest that reports how much of the body has been sent.
class _ProgressMultipartRequest extends http.MultipartRequest {
  _ProgressMultipartRequest(super.method, super.url, this.onProgress);
  final void Function(double progress)? onProgress;

  @override
  http.ByteStream finalize() {
    final total = contentLength;
    var sent = 0;
    final stream = super.finalize();
    if (onProgress == null || total == 0) return stream;
    return http.ByteStream(
      stream.transform(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) {
            sent += data.length;
            sink.add(data);
            onProgress!(sent / total);
          },
        ),
      ),
    );
  }
}

/// Supplies the current access token (if any). Wired to auth in Phase 02.
typedef TokenProvider = FutureOr<String?> Function();

class HttpApiClient implements ApiClient {
  HttpApiClient({
    required this._config,
    http.Client? client,
    this.tokenProvider,
    this.onUnauthorized,
    this.timeout = const Duration(seconds: 20),
    this.uploadTimeout = const Duration(seconds: 90),
  }) : _client = client ?? http.Client();

  final AppConfig _config;
  final http.Client _client;
  final TokenProvider? tokenProvider;

  /// Called when a request that carried a token is rejected with 401
  /// (expired or revoked session).
  final void Function()? onUnauthorized;
  final Duration timeout;
  final Duration uploadTimeout;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(
      '${_config.apiBaseUrl}${AppConfig.apiVersionPath}$path',
    );
    return query == null ? base : base.replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers({String? token}) async {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send((h) => _client.get(_uri(path, query), headers: h));

  @override
  Future<dynamic> post(String path, {Object? body}) =>
      _send((h) => _client.post(_uri(path), headers: h, body: _encode(body)));

  @override
  Future<dynamic> put(String path, {Object? body}) =>
      _send((h) => _client.put(_uri(path), headers: h, body: _encode(body)));

  @override
  Future<dynamic> patch(String path, {Object? body}) =>
      _send((h) => _client.patch(_uri(path), headers: h, body: _encode(body)));

  @override
  Future<dynamic> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    String field = 'file',
    void Function(double progress)? onProgress,
  }) async {
    try {
      final token = await tokenProvider?.call();
      final request = _ProgressMultipartRequest('POST', _uri(path), onProgress)
        ..headers['Accept'] = 'application/json'
        ..files.add(
          http.MultipartFile.fromBytes(
            field,
            bytes,
            filename: filename,
            contentType: MediaType.parse(contentType),
          ),
        );
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      final streamed = await _client.send(request).timeout(uploadTimeout);
      final response = await http.Response.fromStream(streamed);
      try {
        return _decode(response);
      } on UnauthorizedException {
        if (token != null) onUnauthorized?.call();
        rethrow;
      }
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const NetworkException('The upload timed out. Please try again.');
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on FormatException {
      throw const ServerException('Received an unexpected response.');
    }
  }

  @override
  Future<dynamic> delete(String path) =>
      _send((h) => _client.delete(_uri(path), headers: h));

  String? _encode(Object? body) => body == null ? null : jsonEncode(body);

  Future<dynamic> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    try {
      final token = await tokenProvider?.call();
      final response = await request(await _headers(token: token))
          .timeout(timeout);
      try {
        return _decode(response);
      } on UnauthorizedException {
        if (token != null) onUnauthorized?.call();
        rethrow;
      }
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const NetworkException('The request timed out. Please try again.');
    } on SocketException {
      throw const NetworkException();
    } on http.ClientException {
      throw const NetworkException();
    } on FormatException {
      throw const ServerException('Received an unexpected response.');
    }
  }

  dynamic _decode(http.Response response) {
    final status = response.statusCode;
    final raw = utf8.decode(response.bodyBytes);
    final dynamic json = raw.isEmpty ? null : jsonDecode(raw);
    if (status >= 200 && status < 300) return json;

    final detail = json is Map ? json['detail'] : null;
    final message = detail is String ? detail : null;
    switch (status) {
      case 401:
        throw UnauthorizedException(message ?? 'Please sign in to continue.');
      case 403:
        throw ForbiddenException(
          message ?? 'You do not have permission to do that.',
        );
      case 404:
        throw NotFoundException(message ?? 'We could not find that.');
      case 413:
        throw ValidationException(message ?? 'That file is too large.');
      case 415:
        throw ValidationException(
          message ?? 'That file type is not supported.',
        );
      case 429:
        throw const RateLimitedException();
      case 400:
      case 409:
      case 422:
        throw ValidationException(
          message ?? 'Please check the information you entered.',
          fieldErrors: _fieldErrors(detail),
        );
      default:
        throw const ServerException();
    }
  }

  /// Maps FastAPI's validation `detail: [{loc: [...], msg: ...}]` to field → message.
  Map<String, String> _fieldErrors(Object? detail) {
    if (detail is! List) return const {};
    final out = <String, String>{};
    for (final item in detail) {
      if (item is Map && item['loc'] is List && item['msg'] is String) {
        out[(item['loc'] as List).last.toString()] = item['msg'] as String;
      }
    }
    return out;
  }

  void close() => _client.close();
}
