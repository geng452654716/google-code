import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/application/backup/backup_service.dart';
import 'package:google_code/data/backup/backup_crypto_service.dart';
import 'package:google_code/domain/backup/backup.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/totp/totp.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16, 10);
  final current = _payload(
    accounts: [
      _account(
        id: 'current-1',
        issuer: 'Example',
        name: 'same',
        secret: 'AAAA',
      ),
      _account(
        id: 'current-2',
        issuer: 'Other',
        name: 'conflict',
        secret: 'BBBB',
      ),
    ],
    groups: const [
      {'id': 'group-1', 'name': 'Current'},
    ],
    preferences: const {'autoLockMinutes': 5},
  );
  final backup = _payload(
    accounts: [
      _account(id: 'backup-1', issuer: 'example', name: 'SAME', secret: 'AAAA'),
      _account(
        id: 'backup-2',
        issuer: 'Other',
        name: 'conflict',
        secret: 'CCCC',
        groupId: 'group-1',
      ),
      _account(id: 'backup-3', issuer: 'New', name: 'new-user', secret: 'DDDD'),
    ],
    groups: const [
      {'id': 'group-1', 'name': 'Imported'},
    ],
    preferences: const {'autoLockMinutes': 20},
  );
  final service = BackupService(
    cryptoService: _OpenedBackupCrypto(backup, now),
    now: () => now,
  );

  test('preview reports exact duplicates and same-label conflicts', () async {
    final preview = await service.preview(Uint8List(1), 'password', current);
    expect(preview.summary.accountCount, 3);
    expect(preview.summary.newAccountCount, 2);
    expect(preview.summary.exactDuplicateCount, 1);
    expect(preview.summary.conflictCount, 1);
    expect(preview.summary.groupCount, 1);
  });

  test(
    'merge skips exact duplicates and preserves both conflict secrets',
    () async {
      final preview = await service.preview(Uint8List(1), 'password', current);
      final result = service.prepareRestore(
        current: current,
        preview: preview,
        mode: BackupRestoreMode.merge,
      );

      expect(result.addedAccountCount, 2);
      expect(result.skippedDuplicateCount, 1);
      expect(result.conflictCount, 1);
      expect(result.payload.accounts, hasLength(4));
      expect(
        result.payload.accounts
            .where((account) => account.accountName == 'conflict')
            .map((account) => account.secret),
        containsAll(['BBBB', 'CCCC']),
      );
      expect(result.payload.preferences, current.preferences);
      expect(result.payload.groups, hasLength(2));
      final importedConflict = result.payload.accounts.singleWhere(
        (account) => account.secret == 'CCCC',
      );
      expect(importedConflict.groupId, isNot('group-1'));
    },
  );

  test('replace uses the complete backup payload', () async {
    final preview = await service.preview(Uint8List(1), 'password', current);
    final result = service.prepareRestore(
      current: current,
      preview: preview,
      mode: BackupRestoreMode.replace,
    );

    expect(result.payload.accounts.map((account) => account.id), [
      'backup-1',
      'backup-2',
      'backup-3',
    ]);
    expect(result.payload.groups, backup.groups);
    expect(result.payload.preferences, backup.preferences);
    expect(result.payload.updatedAt, now);
  });
}

class _OpenedBackupCrypto extends BackupCryptoService {
  _OpenedBackupCrypto(this.payload, this.createdAt);

  final VaultPayload payload;
  final DateTime createdAt;

  @override
  Future<OpenedBackup> open(Uint8List bytes, String password) async =>
      OpenedBackup(createdAt: createdAt, payload: payload);
}

VaultPayload _payload({
  required List<Account> accounts,
  required List<Map<String, Object?>> groups,
  required Map<String, Object?> preferences,
}) {
  final now = DateTime.utc(2026, 7, 15);
  return VaultPayload(
    schemaVersion: VaultPayload.currentSchemaVersion,
    accounts: accounts,
    groups: groups,
    preferences: preferences,
    createdAt: now,
    updatedAt: now,
  );
}

Account _account({
  required String id,
  required String issuer,
  required String name,
  required String secret,
  String? groupId,
}) {
  final now = DateTime.utc(2026, 7, 15);
  return Account(
    id: id,
    issuer: issuer,
    accountName: name,
    secret: secret,
    algorithm: TotpAlgorithm.sha1,
    digits: 6,
    periodSeconds: 30,
    groupId: groupId,
    sortOrder: 0,
    isPinned: false,
    createdAt: now,
    updatedAt: now,
  );
}
