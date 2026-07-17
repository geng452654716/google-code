import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/google_code_app.dart';
import 'data/repositories/vault_repository_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [localVaultRepositoryOverride],
      child: const GoogleCodeApp(),
    ),
  );
}
