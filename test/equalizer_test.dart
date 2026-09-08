import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_music/core/auth/auth_repository.dart';
import 'package:flutter_music/core/auth/auth_token_store.dart';
import 'package:flutter_music/core/auth/backend_gateway.dart';
import 'package:flutter_music/core/database/app_database.dart';
import 'package:flutter_music/core/player/equalizer_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements BackendGateway {
  List<BackendEqualizerPreset> remotePresets = const [];
  List<BackendEqualizerPreset> uploadedPresets = [];

  @override
  Future<BackendSession> signIn({
    required String username,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<BackendSession> refreshSession(String refreshToken) async {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut(String token) async {}

  @override
  Future<BackendLibrary> syncLibrary(
    BackendSession session,
    List<BackendPlaylist> playlists,
    List<BackendTrack> likedTracks, [
    List<BackendEqualizerPreset> equalizerPresets = const [],
    List<BackendDeletion> deletions = const [],
  ]) async {
    uploadedPresets = List.from(equalizerPresets);

    return BackendLibrary(
      playlists: [],
      likedTracks: [],
      equalizerPresets: remotePresets,
    );
  }
}

class _MemoryTokenStore implements AuthTokenStore {
  StoredAuthTokens? tokens;

  @override
  Future<StoredAuthTokens?> read() async => tokens;

  @override
  Future<void> write(StoredAuthTokens value) async => tokens = value;

  @override
  Future<void> clear() async => tokens = null;
}

void main() {
  group('Equalizer Models', () {
    test('default presets contain 9 presets with 10 bands', () {
      expect(defaultEqualizerPresets.length, 9);
      for (final preset in defaultEqualizerPresets) {
        expect(preset.gains.length, 10);
      }
    });

    test('parseGains correctly decodes JSON list or falls back to zeroes', () {
      final valid = EqualizerPreset.parseGains('[1.5, 2.0, -3.0]');
      expect(valid.length, 10);
      expect(valid[0], 1.5);
      expect(valid[1], 2.0);
      expect(valid[2], -3.0);
      expect(valid[3], 0.0);

      final invalid = EqualizerPreset.parseGains('invalid json');
      expect(invalid.length, 10);
      expect(invalid.every((g) => g == 0.0), isTrue);

      final nullGains = EqualizerPreset.parseGains(null);
      expect(nullGains.length, 10);
      expect(nullGains.every((g) => g == 0.0), isTrue);
    });
  });

  group('Equalizer Database CRUD', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => database.close());

    test('saves and watches custom equalizer presets', () async {
      final now = DateTime(2026, 8, 22);
      await database.saveEqualizerPreset(
        EqualizerPresetsCompanion.insert(
          id: 'custom-1',
          name: '我的低音',
          gainsJson: '[6, 5, 4, 3, 2, 1, 0, 0, 0, 0]',
          preampDb: const Value(-2.5),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final presets = await database.watchEqualizerPresets().first;
      expect(presets.length, 1);
      expect(presets[0].id, 'custom-1');
      expect(presets[0].name, '我的低音');
      expect(presets[0].preampDb, -2.5);

      // Update preset
      await database.saveEqualizerPreset(
        EqualizerPresetsCompanion.insert(
          id: 'custom-1',
          name: '重低音加强',
          gainsJson: '[8, 6, 4, 2, 0, 0, 0, 0, 0, 0]',
          preampDb: const Value(-3.0),
          createdAt: now,
          updatedAt: now.add(const Duration(minutes: 10)),
        ),
      );

      final updated = await database.watchEqualizerPresets().first;
      expect(updated.length, 1);
      expect(updated[0].name, '重低音加强');
      expect(updated[0].preampDb, -3.0);

      // Delete preset
      await database.deleteEqualizerPreset('custom-1');
      final empty = await database.watchEqualizerPresets().first;
      expect(empty.isEmpty, isTrue);
    });
  });

  group('Equalizer Sync', () {
    late AppDatabase database;
    late _FakeGateway gateway;
    late _MemoryTokenStore tokenStore;
    late BackendAuthRepository repository;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      gateway = _FakeGateway();
      tokenStore = _MemoryTokenStore();
      repository = BackendAuthRepository(database, gateway, tokenStore);

      // Mock an active account session
      final now = DateTime.now();
      await database.saveAccount(
        AccountsCompanion.insert(
          id: 'acc-1',
          remoteId: const Value('remote-acc-1'),
          username: 'user@example.com',
          displayName: 'User',
          createdAt: now,
          updatedAt: now,
          isMock: const Value(false),
        ),
      );
      tokenStore.tokens = StoredAuthTokens(
        token: 'token',
        refreshToken: 'refresh',
        expiresAt: now.add(const Duration(hours: 1)),
        accountRemoteId: 'remote-acc-1',
      );
    });

    tearDown(() => database.close());

    test(
      'syncNow uploads local presets and downloads remote presets',
      () async {
        final now = DateTime(2026, 8, 22);
        await database.saveEqualizerPreset(
          EqualizerPresetsCompanion.insert(
            id: 'local-1',
            name: 'Local Preset',
            gainsJson: '[1, 2, 3, 4, 5, 4, 3, 2, 1, 0]',
            preampDb: const Value(-1.0),
            createdAt: now,
            updatedAt: now,
          ),
        );

        gateway.remotePresets = [
          BackendEqualizerPreset(
            remoteId: 'remote-preset-2',
            name: 'Cloud Rock',
            gainsJson: '[4.5, 3.5, 2.0, 0.0, -1.5, -1.0, 1.5, 3.0, 4.0, 4.5]',
            preampDb: -2.0,
            updatedAt: now,
          ),
        ];

        final result = await repository.syncNow();
        expect(result.uploadedPresets, 1);
        expect(result.downloadedPresets, 1);
        expect(gateway.uploadedPresets.length, 1);
        expect(gateway.uploadedPresets[0].name, 'Local Preset');

        final allLocal = await database.allEqualizerPresets();
        expect(allLocal.length, 2);
        expect(allLocal.any((p) => p.name == 'Cloud Rock'), isTrue);
      },
    );
  });
}
