import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_code/app/theme/totp_vault_theme.dart';

void main() {
  test(
    'provides a consistent desktop visual system in light and dark modes',
    () {
      for (final theme in [TotpVaultTheme.light(), TotpVaultTheme.dark()]) {
        expect(theme.useMaterial3, isTrue);
        expect(theme.cardTheme.elevation, 0);
        expect(
          theme.searchBarTheme.constraints,
          const BoxConstraints(minHeight: 44, maxHeight: 44),
        );
        expect(theme.popupMenuTheme.position, PopupMenuPosition.under);
        expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);

        final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
        final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;
        final menuShape = theme.popupMenuTheme.shape! as RoundedRectangleBorder;
        expect(cardShape.borderRadius, BorderRadius.circular(18));
        expect(dialogShape.borderRadius, BorderRadius.circular(22));
        expect(menuShape.borderRadius, BorderRadius.circular(14));
      }
    },
  );
}
