import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/data/vault/vault.dart';

void main() {
  const fastKdf = VaultKdfParameters(memory: 64, iterations: 1, parallelism: 1);

  test(
    'updates payload with a fresh nonce while preserving wrapped DEK',
    () async {
      final service = VaultCryptoService();
      final opened = await service.createOpened(
        {'revision': 1},
        'password123',
        kdf: fastKdf,
      );

      final updated = await service.updatePayload(opened, {'revision': 2});

      expect(
        updated.envelope.wrappedDek.toJson(),
        equals(opened.envelope.wrappedDek.toJson()),
      );
      expect(
        updated.envelope.payload.nonce,
        isNot(equals(opened.envelope.payload.nonce)),
      );
      expect(
        updated.envelope.payload.cipherText,
        isNot(equals(opened.envelope.payload.cipherText)),
      );

      final reopened = await service.open(updated.envelope, 'password123');
      expect(reopened.payload, {'revision': 2});
    },
  );

  test(
    'quick-unlock session owns its DEK after the caller clears its buffer',
    () async {
      final service = VaultCryptoService();
      final created = await service.createOpened(
        {'revision': 1},
        'password123',
        kdf: fastKdf,
      );
      final quickUnlockBuffer = Uint8List.fromList(
        await created.dataEncryptionKey.extractBytes(),
      );

      final opened = await service.openWithDataEncryptionKey(
        created.envelope,
        quickUnlockBuffer,
      );
      quickUnlockBuffer.fillRange(0, quickUnlockBuffer.length, 0);
      final updated = await service.updatePayload(opened, {'revision': 2});

      final reopened = await service.open(updated.envelope, 'password123');
      expect(reopened.payload, {'revision': 2});
      expect(reopened.payloadRequiresReencryption, isFalse);
    },
  );
}
