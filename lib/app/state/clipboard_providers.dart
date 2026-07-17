import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/clipboard/sensitive_clipboard_service.dart';

/// Application-scoped clipboard service whose pending cleanup survives page locks.
final sensitiveClipboardServiceProvider = Provider<SensitiveClipboardService>((
  ref,
) {
  final service = SensitiveClipboardService();
  ref.onDispose(service.dispose);
  return service;
});
