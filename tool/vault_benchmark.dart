import 'dart:io';

import 'package:google_code/data/vault/vault.dart';

/// Measures the production Vault KDF/encryption cost on the current machine.
Future<void> main() async {
  final service = VaultCryptoService();
  final createWatch = Stopwatch()..start();
  final envelope = await service.create({
    'accounts': <Object>[],
  }, 'phase-zero-benchmark-password');
  createWatch.stop();

  final unlockWatch = Stopwatch()..start();
  await service.decrypt(envelope, 'phase-zero-benchmark-password');
  unlockWatch.stop();

  stdout.writeln('vault_create_ms=${createWatch.elapsedMilliseconds}');
  stdout.writeln('vault_unlock_ms=${unlockWatch.elapsedMilliseconds}');
}
