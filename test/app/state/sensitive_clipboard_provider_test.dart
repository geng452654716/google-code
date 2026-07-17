import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/state/providers.dart';
import 'package:google_code/platform/clipboard/sensitive_clipboard_service.dart';

void main() {
  testWidgets(
    'pending cleanup survives disposal of the unlocked account page',
    (tester) async {
      String? clipboard;
      final service = _TrackedClipboardService(
        readText: () async => clipboard,
        writeText: (text) async => clipboard = text,
      );
      final showUnlockedPage = ValueNotifier(true);
      addTearDown(showUnlockedPage.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sensitiveClipboardServiceProvider.overrideWith((ref) {
              ref.onDispose(service.dispose);
              return service;
            }),
          ],
          child: ValueListenableBuilder<bool>(
            valueListenable: showUnlockedPage,
            builder: (context, visible, _) => visible
                ? Consumer(
                    builder: (context, ref, _) {
                      ref.watch(sensitiveClipboardServiceProvider);
                      return const SizedBox();
                    },
                  )
                : const SizedBox(),
          ),
        ),
      );

      await service.writeText(
        'SHARED-SECRET',
        ttl: const Duration(milliseconds: 20),
      );
      showUnlockedPage.value = false;
      await tester.pump();

      expect(service.disposeCount, 0);
      expect(clipboard, 'SHARED-SECRET');
      await tester.pump(const Duration(milliseconds: 30));
      expect(clipboard, isEmpty);

      await tester.pumpWidget(const SizedBox());
      expect(service.disposeCount, 1);
    },
  );
}

/// Test service that exposes application-level disposal without host clipboard IO.
class _TrackedClipboardService extends SensitiveClipboardService {
  _TrackedClipboardService({required super.readText, required super.writeText});

  int disposeCount = 0;

  @override
  void dispose() {
    disposeCount += 1;
    super.dispose();
  }
}
