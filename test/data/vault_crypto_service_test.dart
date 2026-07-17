import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/core/errors/vault_exception.dart';
import 'package:google_code/data/vault/vault.dart';

void main() {
  const fastKdf = VaultKdfParameters(memory: 64, iterations: 1, parallelism: 1);

  test('encrypts, serializes and decrypts a vault payload', () async {
    final service = VaultCryptoService();
    final envelope = await service.create(
      {
        'accounts': [
          {'issuer': 'Example', 'secret': 'JBSWY3DPEHPK3PXP'},
        ],
      },
      'correct horse battery staple',
      kdf: fastKdf,
    );
    final restored = VaultEnvelope.decode(envelope.encode());
    final payload = await service.decrypt(
      restored,
      'correct horse battery staple',
    );
    expect(
      (payload['accounts'] as List).single,
      containsPair('issuer', 'Example'),
    );
    expect(envelope.encode(), isNot(contains('JBSWY3DPEHPK3PXP')));
  });

  test('rejects a wrong password and tampered ciphertext', () async {
    final service = VaultCryptoService();
    final envelope = await service.create(
      {'accounts': <Object>[]},
      'right',
      kdf: fastKdf,
    );
    expect(
      service.decrypt(envelope, 'wrong'),
      throwsA(isA<VaultUnlockException>()),
    );

    final json = jsonDecode(envelope.encode()) as Map<String, Object?>;
    final payload = (json['payload'] as Map).cast<String, Object?>();
    final bytes = base64Decode(payload['cipherText'] as String);
    bytes[0] ^= 1;
    payload['cipherText'] = base64Encode(bytes);
    final tampered = VaultEnvelope.decode(jsonEncode(json));
    expect(
      service.decrypt(tampered, 'right'),
      throwsA(isA<VaultUnlockException>()),
    );
  });

  test(
    'file store keeps a backup and recovers from malformed primary',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'google_code_vault_test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = VaultFileStore(File('${directory.path}/vault.json'));
      final service = VaultCryptoService();
      final first = await service.create(
        {'revision': 1},
        'password',
        kdf: fastKdf,
      );
      final second = await service.create(
        {'revision': 2},
        'password',
        kdf: fastKdf,
      );
      await store.write(first);
      await store.write(second);
      await store.file.writeAsString('{broken');

      final recovered = await store.read();
      final payload = await service.decrypt(recovered, 'password');
      expect(payload['revision'], 1);
    },
  );
}
