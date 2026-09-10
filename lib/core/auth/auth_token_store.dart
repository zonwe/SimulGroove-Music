import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredAuthTokens {
  const StoredAuthTokens({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
    required this.accountRemoteId,
    this.trackMatchKey,
  });

  final String token;
  final String refreshToken;
  final DateTime expiresAt;
  final String accountRemoteId;
  final String? trackMatchKey;
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
  static const _accountRemoteIdKey = 'auth.account_remote_id';
  static const _trackMatchKey = 'auth.track_match_key';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredAuthTokens?> read() async {
    final values = await Future.wait([
      _storage.read(key: _accessTokenKey),
      _storage.read(key: _refreshTokenKey),
      _storage.read(key: _expiresAtKey),
      _storage.read(key: _accountRemoteIdKey),
      _storage.read(key: _trackMatchKey),
    ]);
    final token = values[0];
    final refreshToken = values[1];
    final expiresAt = DateTime.tryParse(values[2] ?? '');
    final accountRemoteId = values[3];
    if (token == null ||
        refreshToken == null ||
        expiresAt == null ||
        accountRemoteId == null ||
        accountRemoteId.isEmpty) {
      return null;
    }
    return StoredAuthTokens(
      token: token,
      refreshToken: refreshToken,
      expiresAt: expiresAt.toUtc(),
      accountRemoteId: accountRemoteId,
      trackMatchKey: values[4],
    );
  }

  @override
  Future<void> write(StoredAuthTokens tokens) async {
    // The account id is a commit marker written last. If an earlier secure
    // storage write fails, restoration sees an account mismatch and rejects
    // the partially updated token set instead of combining two accounts.
    await _storage.write(key: _accessTokenKey, value: tokens.token);
    await _storage.write(key: _refreshTokenKey, value: tokens.refreshToken);
    await _storage.write(
      key: _expiresAtKey,
      value: tokens.expiresAt.toUtc().toIso8601String(),
    );
    if (tokens.trackMatchKey case final value?) {
      await _storage.write(key: _trackMatchKey, value: value);
    } else {
      await _storage.delete(key: _trackMatchKey);
    }
    await _storage.write(
      key: _accountRemoteIdKey,
      value: tokens.accountRemoteId,
    );
  }

  @override
  Future<void> clear() => Future.wait([
    _storage.delete(key: _accessTokenKey),
    _storage.delete(key: _refreshTokenKey),
    _storage.delete(key: _expiresAtKey),
    _storage.delete(key: _accountRemoteIdKey),
    _storage.delete(key: _trackMatchKey),
  ]);
}
