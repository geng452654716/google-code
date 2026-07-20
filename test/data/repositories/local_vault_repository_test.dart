import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/core/errors/vault_exception.dart';
import 'package:google_code/data/repositories/local_vault_repository.dart';
import 'package:google_code/data/vault/vault.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/repositories/vault_repository.dart';
import 'package:google_code/domain/totp/totp.dart';

void main() {
  const fastKdf = VaultKdfParameters(memory: 64, iterations: 1, parallelism: 1);

  late Directory directory;
  late File vaultFile;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('google_code_repo_test');
    vaultFile = File('${directory.path}/vault.json');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  LocalVaultRepository createRepository() =>
      LocalVaultRepository(() async => vaultFile, kdfParameters: fastKdf);

  test('creates, saves, locks and unlocks persisted accounts', () async {
    final repository = createRepository();
    expect(await repository.inspect(), VaultAvailability.missing);

    final initial = await repository.create('password123');
    expect(initial.accounts, isEmpty);
    expect(await repository.inspect(), VaultAvailability.present);

    final now = DateTime.utc(2026, 7, 16, 10);
    final account = Account(
      id: 'account-1',
      issuer: 'Example',
      accountName: 'alice@example.com',
      secret: 'JBSWY3DPEHPK3PXP',
      algorithm: TotpAlgorithm.sha1,
      digits: 6,
      periodSeconds: 30,
      sortOrder: 0,
      isPinned: false,
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(
      initial.copyWith(accounts: [account], updatedAt: now),
    );
    repository.lock();

    final reopenedRepository = createRepository();
    expect(await reopenedRepository.inspect(), VaultAvailability.present);
    final restored = await reopenedRepository.unlock('password123');
    expect(restored.accounts.single.toJson(), account.toJson());
  });

  test(
    'exports the active DEK and unlocks without the master password',
    () async {
      final repository = createRepository();
      final initial = await repository.create('password123');
      final quickUnlockKey = await repository.exportQuickUnlockKey();
      expect(quickUnlockKey, hasLength(32));

      final updatedAt = DateTime.utc(2026, 7, 16, 14);
      await repository.save(initial.copyWith(updatedAt: updatedAt));
      repository.lock();

      final reopenedRepository = createRepository();
      final restored = await reopenedRepository.unlockWithQuickUnlockKey(
        quickUnlockKey,
      );
      expect(restored.updatedAt, updatedAt);

      quickUnlockKey.fillRange(0, quickUnlockKey.length, 0);
    },
  );

  test('rejects an invalid quick unlock DEK', () async {
    final repository = createRepository();
    await repository.create('password123');
    repository.lock();

    expect(
      createRepository().unlockWithQuickUnlockKey(Uint8List(32)),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test('verifies the password without replacing the opened Vault', () async {
    final repository = createRepository();
    final initial = await repository.create('password123');

    expect(await repository.verifyPassword('password123'), isTrue);
    expect(await repository.verifyPassword('wrong-password'), isFalse);

    final updatedAt = DateTime.utc(2026, 7, 16, 12);
    await repository.save(initial.copyWith(updatedAt: updatedAt));
    repository.lock();

    final restored = await createRepository().unlock('password123');
    expect(restored.updatedAt, updatedAt);
  });

  test(
    'returns false when password verification has no persisted Vault',
    () async {
      expect(await createRepository().verifyPassword('password123'), isFalse);
    },
  );

  test('rejects a wrong password', () async {
    final repository = createRepository();
    final initial = await repository.create('password123');
    await repository.save(
      initial.copyWith(updatedAt: DateTime.utc(2026, 7, 16, 15)),
    );
    repository.lock();

    expect(
      repository.unlock('not-the-password'),
      throwsA(
        isA<VaultUnlockException>().having(
          (error) => error.kind,
          'kind',
          VaultUnlockFailureKind.invalidCredential,
        ),
      ),
    );
  });

  test(
    'recovers from authenticated primary corruption through the backup',
    () async {
      final repository = createRepository();
      final initial = await repository.create('password123');
      final primaryRevision = initial.copyWith(
        updatedAt: DateTime.utc(2026, 7, 16, 15),
      );
      await repository.save(primaryRevision);
      repository.lock();

      final encoded = await vaultFile.readAsString();
      final envelope = VaultEnvelope.decode(encoded);
      final tamperedCipherText = List<int>.from(envelope.payload.cipherText)
        ..[0] ^= 1;
      final tampered = VaultEnvelope(
        version: envelope.version,
        kdf: envelope.kdf,
        salt: envelope.salt,
        wrappedDek: envelope.wrappedDek,
        payload: VaultCipherBox(
          nonce: envelope.payload.nonce,
          cipherText: tamperedCipherText,
          mac: envelope.payload.mac,
        ),
      );
      await vaultFile.writeAsString(tampered.encode(), flush: true);

      final recoveredRepository = createRepository();
      final recovered = await recoveredRepository.unlock('password123');
      expect(recovered.updatedAt, initial.updatedAt);

      final backupBeforeSave = await File(
        '${vaultFile.path}.bak',
      ).readAsString();
      final repaired = recovered.copyWith(
        updatedAt: DateTime.utc(2026, 7, 16, 16),
      );
      await recoveredRepository.save(repaired);

      expect(
        await File('${vaultFile.path}.bak').readAsString(),
        backupBeforeSave,
      );
      final reopened = await createRepository().unlock('password123');
      expect(reopened.updatedAt, repaired.updatedAt);
    },
  );

  test(
    'classifies two unreadable Vault copies without guessing password',
    () async {
      await vaultFile.writeAsString('{broken', flush: true);
      await File(
        '${vaultFile.path}.bak',
      ).writeAsString('{also-broken', flush: true);

      expect(
        createRepository().unlock('password123'),
        throwsA(
          isA<VaultUnlockException>().having(
            (error) => error.kind,
            'kind',
            VaultUnlockFailureKind.unreadableVault,
          ),
        ),
      );
    },
  );

  test('rejects saving while locked', () async {
    final repository = createRepository();
    final payload = await repository.create('password123');
    repository.lock();

    expect(repository.save(payload), throwsA(isA<VaultUnlockException>()));
  });
}
