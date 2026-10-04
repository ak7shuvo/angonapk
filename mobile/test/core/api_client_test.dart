import 'dart:convert';

import 'package:angon/config/app_config.dart';
import 'package:angon/core/errors/app_exception.dart';
import 'package:angon/core/network/api_client.dart';
import 'package:angon/repositories/health_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: 'http://api.test',
);

HttpApiClient _client(MockClientHandler handler, {TokenProvider? token}) =>
    HttpApiClient(
      config: _config,
      client: MockClient(handler),
      tokenProvider: token,
    );

void main() {
  test('builds versioned URL and parses JSON', () async {
    late Uri seen;
    final api = _client((req) async {
      seen = req.url;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final json = await api.get('/health');
    expect(seen.toString(), 'http://api.test/api/v1/health');
    expect(json, {'ok': true});
  });

  test('sends bearer token when available', () async {
    String? auth;
    final api = _client((req) async {
      auth = req.headers['Authorization'];
      return http.Response('{}', 200);
    }, token: () => 'abc');
    await api.get('/x');
    expect(auth, 'Bearer abc');
  });

  test('decodes UTF-8 Bengali bodies', () async {
    final api = _client(
      (_) async =>
          http.Response.bytes(utf8.encode(jsonEncode({'name': 'জাফলং'})), 200),
    );
    expect((await api.get('/x'))['name'], 'জাফলং');
  });

  test('maps status codes to typed exceptions', () async {
    Future<Object> errorFor(
      int code, [
      String body = '{"detail":"nope"}',
    ]) async {
      final api = _client((_) async => http.Response(body, code));
      try {
        await api.get('/x');
      } catch (e) {
        return e;
      }
      fail('expected exception');
    }

    expect(await errorFor(401), isA<UnauthorizedException>());
    expect(await errorFor(403), isA<ForbiddenException>());
    expect(await errorFor(404), isA<NotFoundException>());
    expect(await errorFor(500), isA<ServerException>());
    final v = await errorFor(
      422,
      '{"detail":[{"loc":["body","email"],"msg":"invalid email"}]}',
    );
    expect(v, isA<ValidationException>());
    expect((v as ValidationException).fieldErrors['email'], 'invalid email');
  });

  test('maps transport failure to NetworkException', () async {
    final api = _client((_) async => throw http.ClientException('down'));
    expect(api.get('/x'), throwsA(isA<NetworkException>()));
  });

  test('HealthRepository parses health response', () async {
    final api = _client(
      (_) async => http.Response(
        jsonEncode({
          'status': 'ok',
          'environment': 'development',
          'database': 'ok',
        }),
        200,
      ),
    );
    final health = await HealthRepository(api).check();
    expect(health.isHealthy, isTrue);
    expect(health.database, 'ok');
  });
}
