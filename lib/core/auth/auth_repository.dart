import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

abstract interface class AuthRepository {
  Future<void> signIn({required String username, required String password});
}

class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._database);

  final AppDatabase _database;
  final Uuid _uuid = const Uuid();

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final normalized = username.trim();
    if (normalized.isEmpty || password.isEmpty) {
      throw const FormatException('请输入账号和密码');
    }
    final now = DateTime.now();
    await _database.saveAccount(
      AccountsCompanion.insert(
        id: _uuid.v5(Namespace.url.value, 'mock-account:$normalized'),
        username: normalized,
        displayName: normalized.split('@').first,
        createdAt: now,
        updatedAt: now,
        isMock: const Value(true),
      ),
    );
  }
}
