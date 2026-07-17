import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../app/state/vault_session_controller.dart';
import 'local_vault_repository.dart';

/// Overrides the abstract repository provider with the device-local Vault.
final localVaultRepositoryOverride = vaultRepositoryProvider.overrideWith(
  (ref) => LocalVaultRepository(() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/google-code/vault.gcvault');
  }),
);
