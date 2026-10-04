import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the access token. Implementations must keep it in secure storage.
abstract interface class TokenStorage {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Android Keystore / iOS Keychain backed storage.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'angon_access_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Non-persistent storage for tests only.
class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage([this._token]);
  String? _token;

  /// Synchronous peek, for test doubles.
  String? get current => _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
