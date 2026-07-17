import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/domain/entities/entities.dart';
import 'package:google_code/domain/totp/totp.dart';

void main() {
  test('serializes and restores the complete Vault payload', () {
    final createdAt = DateTime.utc(2026, 7, 16, 8);
    final updatedAt = DateTime.utc(2026, 7, 16, 9);
    final payload = VaultPayload(
      schemaVersion: VaultPayload.currentSchemaVersion,
      accounts: [
        Account(
          id: 'account-1',
          issuer: 'Example',
          accountName: 'alice@example.com',
          secret: 'JBSWY3DPEHPK3PXP',
          algorithm: TotpAlgorithm.sha256,
          digits: 8,
          periodSeconds: 45,
          groupId: 'group-1',
          sortOrder: 2,
          isPinned: true,
          createdAt: createdAt,
          updatedAt: updatedAt,
          lastUsedAt: updatedAt,
        ),
      ],
      groups: const [
        {'id': 'group-1', 'name': 'Work'},
      ],
      preferences: const {'autoLockMinutes': 10, 'theme': 'dark'},
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final restored = VaultPayload.fromJson(payload.toJson());

    expect(restored.toJson(), equals(payload.toJson()));
    expect(restored.accounts.single.algorithm, TotpAlgorithm.sha256);
    expect(restored.accounts.single.lastUsedAt, updatedAt);
  });

  test('rejects an unsupported payload schema', () {
    final json = VaultPayload.empty(DateTime.utc(2026, 7, 16)).toJson();
    json['schemaVersion'] = 99;

    expect(() => VaultPayload.fromJson(json), throwsFormatException);
  });
}
