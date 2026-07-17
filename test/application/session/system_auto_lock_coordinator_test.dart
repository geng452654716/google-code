import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/application/session/system_auto_lock_coordinator.dart';
import 'package:google_code/platform/session/system_session_event_service.dart';

void main() {
  test(
    'ignores native security events while the Vault is already locked',
    () async {
      final service = _FakeSystemSessionEventService();
      addTearDown(service.dispose);
      final calls = <String>[];
      final coordinator = SystemAutoLockCoordinator(
        eventService: service,
        isVaultUnlocked: () => false,
        clearSensitiveRoutes: () => calls.add('clear'),
        lockVault: () => calls.add('lock'),
      );
      addTearDown(coordinator.dispose);

      await coordinator.start();
      service.emit(SystemSessionEvent.screenLocked);

      expect(calls, isEmpty);
    },
  );

  test('clears sensitive routes before locking an unlocked Vault', () async {
    final service = _FakeSystemSessionEventService();
    addTearDown(service.dispose);
    final calls = <String>[];
    final coordinator = SystemAutoLockCoordinator(
      eventService: service,
      isVaultUnlocked: () => true,
      clearSensitiveRoutes: () => calls.add('clear'),
      lockVault: () => calls.add('lock'),
    );
    addTearDown(coordinator.dispose);

    await coordinator.start();
    service.emit(SystemSessionEvent.sessionDisconnected);

    expect(calls, ['clear', 'lock']);
  });

  test('does not lock twice after the first event closes the Vault', () async {
    final service = _FakeSystemSessionEventService();
    addTearDown(service.dispose);
    final calls = <String>[];
    var isUnlocked = true;
    final coordinator = SystemAutoLockCoordinator(
      eventService: service,
      isVaultUnlocked: () => isUnlocked,
      clearSensitiveRoutes: () => calls.add('clear'),
      lockVault: () {
        calls.add('lock');
        isUnlocked = false;
      },
    );
    addTearDown(coordinator.dispose);

    await coordinator.start();
    service
      ..emit(SystemSessionEvent.screenLocked)
      ..emit(SystemSessionEvent.systemSleeping);

    expect(calls, ['clear', 'lock']);
  });

  test('stops handling native events after coordinator disposal', () async {
    final service = _FakeSystemSessionEventService();
    addTearDown(service.dispose);
    final calls = <String>[];
    final coordinator = SystemAutoLockCoordinator(
      eventService: service,
      isVaultUnlocked: () => true,
      clearSensitiveRoutes: () => calls.add('clear'),
      lockVault: () => calls.add('lock'),
    );

    await coordinator.start();
    await coordinator.dispose();
    service.emit(SystemSessionEvent.systemSleeping);

    expect(calls, isEmpty);
  });

  test(
    'native registration failure does not block application startup',
    () async {
      final service = _FakeSystemSessionEventService(throwOnStart: true);
      addTearDown(service.dispose);
      final calls = <String>[];
      final coordinator = SystemAutoLockCoordinator(
        eventService: service,
        isVaultUnlocked: () => true,
        clearSensitiveRoutes: () => calls.add('clear'),
        lockVault: () => calls.add('lock'),
      );
      addTearDown(coordinator.dispose);

      await expectLater(coordinator.start(), completes);
      service.emit(SystemSessionEvent.screenLocked);

      expect(calls, isEmpty);
    },
  );
}

/// Controllable in-memory source for deterministic coordinator tests.
class _FakeSystemSessionEventService implements SystemSessionEventService {
  _FakeSystemSessionEventService({this.throwOnStart = false});

  final bool throwOnStart;
  final _controller = StreamController<SystemSessionEvent>.broadcast(
    sync: true,
  );
  bool _isDisposed = false;

  @override
  Stream<SystemSessionEvent> get events => _controller.stream;

  @override
  Future<void> start() async {
    if (throwOnStart) throw StateError('Native registration failed.');
  }

  /// Publishes one normalized operating-system event to active listeners.
  void emit(SystemSessionEvent event) {
    if (!_isDisposed) _controller.add(event);
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _controller.close();
  }
}
