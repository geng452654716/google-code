import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/share/account_share_service.dart';
import '../../platform/files/account_share_file_saver.dart';

/// In-memory account share material generator.
final accountShareServiceProvider = Provider<AccountShareService>(
  (ref) => AccountShareService(),
);

/// User-selected QR PNG destination isolated behind a testable boundary.
final accountShareFileSaverProvider = Provider<AccountShareFileSaver>(
  (ref) => FileSelectorAccountShareFileSaver(),
);
