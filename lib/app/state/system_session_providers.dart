import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/session/system_session_event_service.dart';

/// Application-scoped native session event source used by automatic locking.
final systemSessionEventServiceProvider = Provider<SystemSessionEventService>((
  ref,
) {
  final service = MethodChannelSystemSessionEventService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
