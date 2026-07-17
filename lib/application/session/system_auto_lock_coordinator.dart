import 'dart:async';

import '../../platform/session/system_session_event_service.dart';

/// Converts native session security events into one immediate Vault lock.
class SystemAutoLockCoordinator {
  SystemAutoLockCoordinator({
    required this.eventService,
    required this.isVaultUnlocked,
    required this.clearSensitiveRoutes,
    required this.lockVault,
  });

  /// Native system-session event source.
  final SystemSessionEventService eventService;

  /// Reads current session state when an event arrives.
  final bool Function() isVaultUnlocked;

  /// Removes every modal route before decrypted application state is dropped.
  final void Function() clearSensitiveRoutes;

  /// Clears the repository and application Vault session.
  final void Function() lockVault;

  StreamSubscription<SystemSessionEvent>? _subscription;

  /// Starts listening before registering the native handler to avoid event loss.
  Future<void> start() async {
    if (_subscription != null) return;
    _subscription = eventService.events.listen(_handleEvent);
    try {
      await eventService.start();
    } on Object {
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  /// Stops this coordinator without taking ownership of the provider service.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _handleEvent(SystemSessionEvent event) {
    if (!isVaultUnlocked()) return;
    clearSensitiveRoutes();
    lockVault();
  }
}
