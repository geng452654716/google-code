import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/application/security/quick_unlock_service.dart';
import 'package:google_code/core/errors/vault_exception.dart';
import 'package:google_code/domain/entities/vault_payload.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/platform/auth/local_authentication_service.dart';
import 'package:google_code/platform/security/secure_key_store.dart';

void main() {
  late _QuickUnlockRepository repository;
  late _Authentication authentication;
  late _KeyStore keyStore;
  late QuickUnlockService service;

  setUp(() {
    repository = _QuickUnlockRepository();
    authentication = _Authentication();
    keyStore = _KeyStore();
    service = QuickUnlockService(
      repository: repository,
      authentication: authentication,
      keyStore: keyStore,
    );
  });

  test(
    'enables only after master password and device authentication',
    () async {
      expect(
        await service.enable('wrong-password'),
        QuickUnlockEnableResult.wrongPassword,
      );
      expect(authentication.authenticateCount, 0);
      expect(keyStore.written, isNull);

      authentication.nextResult = DeviceAuthenticationResult.cancelled;
      expect(
        await service.enable('password123'),
        QuickUnlockEnableResult.cancelled,
      );
      expect(repository.exportCount, 0);
      expect(keyStore.written, isNull);

      authentication.nextResult = DeviceAuthenticationResult.authenticated;
      expect(
        await service.enable('password123'),
        QuickUnlockEnableResult.enabled,
      );
      expect(keyStore.written, repository.expectedKey);
      expect(repository.exportedReference, everyElement(0));
    },
  );

  test('unlocks with a protected DEK and clears the temporary copy', () async {
    keyStore.stored = Uint8List.fromList(repository.expectedKey);

    final attempt = await service.unlock();

    expect(attempt.status, QuickUnlockAttemptStatus.success);
    expect(attempt.payload, same(repository.payload));
    expect(repository.receivedUnlockKey, repository.expectedKey);
    expect(keyStore.lastReadReference, everyElement(0));
    expect(keyStore.deleteCount, 0);
  });

  test(
    'authentication cancellation keeps valid quick unlock material',
    () async {
      keyStore.stored = Uint8List.fromList(repository.expectedKey);
      authentication.nextResult = DeviceAuthenticationResult.cancelled;

      final attempt = await service.unlock();

      expect(attempt.status, QuickUnlockAttemptStatus.cancelled);
      expect(keyStore.deleteCount, 0);
      expect(repository.quickUnlockCount, 0);
    },
  );

  test('invalid or stale DEK is deleted and falls back safely', () async {
    keyStore.stored = Uint8List(32)..fillRange(0, 32, 9);
    repository.rejectQuickUnlock = true;

    final attempt = await service.unlock();

    expect(attempt.status, QuickUnlockAttemptStatus.invalidKey);
    expect(keyStore.deleteCount, 1);
    expect(keyStore.stored, isNull);
  });

  test('sensitive reauthentication requires configured quick unlock', () async {
    expect(
      await service.reauthenticate(reason: 'share'),
      DeviceAuthenticationResult.unavailable,
    );
    expect(authentication.authenticateCount, 0);

    keyStore.stored = Uint8List.fromList(repository.expectedKey);
    expect(
      await service.reauthenticate(reason: 'share'),
      DeviceAuthenticationResult.authenticated,
    );
    expect(authentication.authenticateCount, 1);
    expect(authentication.lastReason, 'share');
  });

  test('disable removes only the device quick unlock material', () async {
    keyStore.stored = Uint8List.fromList(repository.expectedKey);

    expect(await service.disable(), isTrue);
    expect(keyStore.stored, isNull);
    expect(keyStore.deleteCount, 1);
    expect(repository.lockCount, 0);
  });
}

class _QuickUnlockRepository implements VaultRepository {
  final payload = VaultPayload.empty(DateTime.utc(2026, 7, 16));
  final expectedKey = List<int>.generate(32, (index) => index);

  Uint8List? exportedReference;
  List<int>? receivedUnlockKey;
  int exportCount = 0;
  int quickUnlockCount = 0;
  int lockCount = 0;
  bool rejectQuickUnlock = false;

  @override
  Future<VaultAvailability> inspect() async => VaultAvailability.present;

  @override
  Future<VaultPayload> create(String password) async => payload;

  @override
  Future<VaultPayload> unlock(String password) async => payload;

  @override
  Future<VaultPayload> unlockWithQuickUnlockKey(Uint8List keyBytes) async {
    quickUnlockCount += 1;
    receivedUnlockKey = List<int>.from(keyBytes);
    if (rejectQuickUnlock) throw const VaultUnlockException();
    return payload;
  }

  @override
  Future<Uint8List> exportQuickUnlockKey() async {
    exportCount += 1;
    return exportedReference = Uint8List.fromList(expectedKey);
  }

  @override
  Future<bool> verifyPassword(String password) async =>
      password == 'password123';

  @override
  Future<void> save(VaultPayload payload) async {}

  @override
  void lock() => lockCount += 1;
}

class _Authentication implements LocalAuthenticationService {
  DeviceAuthenticationAvailability availability =
      DeviceAuthenticationAvailability.available;
  DeviceAuthenticationResult nextResult =
      DeviceAuthenticationResult.authenticated;
  int authenticateCount = 0;
  String? lastReason;

  @override
  String get displayName => 'Test Device Auth';

  @override
  Future<DeviceAuthenticationAvailability> inspect() async => availability;

  @override
  Future<DeviceAuthenticationResult> authenticate({
    required String reason,
  }) async {
    authenticateCount += 1;
    lastReason = reason;
    return nextResult;
  }
}

class _KeyStore implements SecureKeyStore {
  Uint8List? stored;
  Uint8List? written;
  Uint8List? lastReadReference;
  int deleteCount = 0;

  @override
  Future<bool> containsQuickUnlockKey() async => stored != null;

  @override
  Future<Uint8List?> readQuickUnlockKey() async {
    final value = stored;
    if (value == null) return null;
    return lastReadReference = Uint8List.fromList(value);
  }

  @override
  Future<void> writeQuickUnlockKey(Uint8List keyBytes) async {
    written = Uint8List.fromList(keyBytes);
    stored = Uint8List.fromList(keyBytes);
  }

  @override
  Future<void> deleteQuickUnlockKey() async {
    deleteCount += 1;
    stored = null;
  }
}
