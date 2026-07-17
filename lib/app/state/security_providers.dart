import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/security/quick_unlock_service.dart';
import '../../platform/auth/local_authentication_service.dart';
import '../../platform/security/secure_key_store.dart';
import 'vault_session_controller.dart';

/// Device-owner authentication implementation used by quick unlock.
final localAuthenticationServiceProvider = Provider<LocalAuthenticationService>(
  (ref) => SystemLocalAuthenticationService(),
);

/// Device secure storage implementation used only for the quick-unlock DEK.
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => MethodChannelSecureKeyStore(),
);

/// Application service coordinating device authentication and Vault access.
final quickUnlockServiceProvider = Provider<QuickUnlockService>(
  (ref) => QuickUnlockService(
    repository: ref.watch(vaultRepositoryProvider),
    authentication: ref.watch(localAuthenticationServiceProvider),
    keyStore: ref.watch(secureKeyStoreProvider),
  ),
);
