import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/application/backup/backup_exception.dart';
import 'package:google_code/data/backup/backup_crypto_service.dart';
import 'package:google_code/data/backup/backup_envelope.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/totp/totp.dart';

void main() {
  const testKdf = BackupKdfParameters(memoryKiB: 8192, iterations: 1);
  final payload = _payload();

  test('encrypted backup round-trips without clear account data', () async {
    final service = BackupCryptoService();
    final bytes = await service.create(
      payload,
      'backup-password',
      createdAt: DateTime.utc(2026, 7, 16, 8),
      kdf: testKdf,
    );

    final encoded = utf8.decode(bytes);
    expect(encoded, isNot(contains('JBSWY3DPEHPK3PXP')));
    expect(encoded, isNot(contains('alice@example.com')));
    expect(encoded, isNot(contains('Example')));

    final opened = await service.open(bytes, 'backup-password');
    expect(opened.createdAt, DateTime.utc(2026, 7, 16, 8));
    expect(opened.payload.toJson(), payload.toJson());
  });

  test('wrong password and tampering fail authentication', () async {
    final service = BackupCryptoService();
    final bytes = await service.create(
      payload,
      'backup-password',
      kdf: testKdf,
    );

    await expectLater(
      service.open(bytes, 'wrong-password'),
      throwsA(
        isA<BackupException>().having(
          (error) => error.kind,
          'kind',
          BackupFailureKind.invalidPasswordOrCorrupted,
        ),
      ),
    );

    final json = (jsonDecode(utf8.decode(bytes)) as Map)
        .cast<String, Object?>();
    final encryptedPayload = (json['payload'] as Map).cast<String, Object?>();
    final cipherText = base64Decode(encryptedPayload['cipherText'] as String);
    cipherText[0] ^= 0x01;
    encryptedPayload['cipherText'] = base64Encode(cipherText);
    final tampered = Uint8List.fromList(utf8.encode(jsonEncode(json)));

    await expectLater(
      service.open(tampered, 'backup-password'),
      throwsA(
        isA<BackupException>().having(
          (error) => error.kind,
          'kind',
          BackupFailureKind.invalidPasswordOrCorrupted,
        ),
      ),
    );
  });

  test('rejects non-backup and future-version files safely', () async {
    final service = BackupCryptoService();
    await expectLater(
      service.open(Uint8List.fromList(utf8.encode('{}')), 'password'),
      throwsA(
        isA<BackupException>().having(
          (error) => error.kind,
          'kind',
          BackupFailureKind.invalidFormat,
        ),
      ),
    );

    final bytes = await service.create(payload, 'password', kdf: testKdf);
    final json = (jsonDecode(utf8.decode(bytes)) as Map)
        .cast<String, Object?>();
    json['formatVersion'] = BackupEnvelope.currentFormatVersion + 1;
    await expectLater(
      service.open(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
        'password',
      ),
      throwsA(
        isA<BackupException>().having(
          (error) => error.kind,
          'kind',
          BackupFailureKind.unsupportedVersion,
        ),
      ),
    );
  });

  test('rejects files above the in-memory size limit before parsing', () async {
    final service = BackupCryptoService();
    await expectLater(
      service.open(
        Uint8List(BackupCryptoService.maxBackupBytes + 1),
        'password',
      ),
      throwsA(
        isA<BackupException>().having(
          (error) => error.kind,
          'kind',
          BackupFailureKind.fileTooLarge,
        ),
      ),
    );
  });
}

VaultPayload _payload() {
  final now = DateTime.utc(2026, 7, 16);
  return VaultPayload.empty(now).copyWith(
    accounts: [
      Account(
        id: 'account-1',
        issuer: 'Example',
        accountName: 'alice@example.com',
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: TotpAlgorithm.sha1,
        digits: 6,
        periodSeconds: 30,
        groupId: 'group-1',
        sortOrder: 4,
        isPinned: true,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    groups: const [
      {'id': 'group-1', 'name': 'Work'},
    ],
    preferences: const {'autoLockMinutes': 10, 'locale': 'zh'},
  );
}
