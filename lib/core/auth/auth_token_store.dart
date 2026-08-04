import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredAuthTokens {
  const StoredAuthTokens({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String token;
  final String refreshToken;
  final DateTime expiresAt;
}

abstract interface class AuthTokenStore {
  Future<StoredAuthTokens?> read();

  Future<void> write(StoredAuthTokens tokens);

  Future<void> clear();
}

class SecureAuthTokenStore implements AuthTokenStore {
  SecureAuthTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessTokenKey = 'auth.access_token';
  static const _refreshTokenKey = 'auth.refresh_token';
  static const _expiresAtKey = 'auth.expires_at';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredAuthTokens?> read() async {
    final values = await Future.wait([
      _storage.read(key: _accessTokenKey),
      _storage.read(key: _refreshTokenKey),
      _storage.read(key: _expiresAtKey),
    ]);
    final token = values[0];
    final refreshToken = values[1];
    final expiresAt = DateTime.tryParse(values[2] ?? '');
    if (token == null || refreshToken == null || expiresAt == null) return null;
    return StoredAuthTokens(
      token: token,
      refreshToken: refreshToken,
      expiresAt: expiresAt.toUtc(),
    );
  }

  @override
  Future<void> write(StoredAuthTokens tokens) => Future.wait([
    _storage.write(key: _accessTokenKey, value: tokens.token),
    _storage.write(key: _refreshTokenKey, value: tokens.refreshToken),
    _storage.write(
      key: _expiresAtKey,
      value: tokens.expiresAt.toUtc().toIso8601String(),
    ),
  ]);

  @override
  Future<void> clear() => Future.wait([
    _storage.delete(key: _accessTokenKey),
    _storage.delete(key: _refreshTokenKey),
    _storage.delete(key: _expiresAtKey),
  ]);
}
