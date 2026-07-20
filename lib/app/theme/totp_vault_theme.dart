import 'package:flutter/material.dart';

/// Centralized visual system for the desktop-first TOTP Vault interface.
class TotpVaultTheme {
  TotpVaultTheme._();

  static const _seed = Color(0xFF5968D8);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final generated = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final colors = generated.copyWith(
      primary: isDark ? const Color(0xFFBEC6FF) : const Color(0xFF5262C9),
      onPrimary: isDark ? const Color(0xFF202F78) : Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF303F8E)
          : const Color(0xFFE5E9FF),
      onPrimaryContainer: isDark
          ? const Color(0xFFE1E5FF)
          : const Color(0xFF27368C),
      secondary: isDark ? const Color(0xFFC3C6D5) : const Color(0xFF5C6275),
      secondaryContainer: isDark
          ? const Color(0xFF343746)
          : const Color(0xFFE8EAF2),
      onSecondaryContainer: isDark
          ? const Color(0xFFE7E8F1)
          : const Color(0xFF353949),
      surface: isDark ? const Color(0xFF14161D) : const Color(0xFFF8F9FD),
      surfaceContainerLowest: isDark ? const Color(0xFF11131A) : Colors.white,
      surfaceContainerLow: isDark
          ? const Color(0xFF191C24)
          : const Color(0xFFF7F8FC),
      surfaceContainer: isDark
          ? const Color(0xFF1E212A)
          : const Color(0xFFF0F2F8),
      surfaceContainerHigh: isDark
          ? const Color(0xFF252934)
          : const Color(0xFFE9ECF4),
      surfaceContainerHighest: isDark
          ? const Color(0xFF2C303D)
          : const Color(0xFFE1E5EF),
      outline: isDark ? const Color(0xFF8E92A1) : const Color(0xFF777B8A),
      outlineVariant: isDark
          ? const Color(0xFF383C49)
          : const Color(0xFFD9DDE8),
    );
    final base = ThemeData(
      brightness: brightness,
      colorScheme: colors,
      useMaterial3: true,
    );
    final textTheme = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    final rounded12 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return base.copyWith(
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF0F1117)
          : const Color(0xFFF3F5FA),
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 18,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.42 : 0.16),
        backgroundColor: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: colors.outlineVariant),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: colors.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.error, width: 1.5),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerLowest),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: colors.outlineVariant)),
        shape: WidgetStatePropertyAll(rounded12),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14),
        ),
        constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
        hintStyle: WidgetStatePropertyAll(
          textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
        menuPadding: const EdgeInsets.symmetric(vertical: 6),
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        iconColor: colors.onSurfaceVariant,
        iconSize: 20,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: rounded12,
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: rounded12,
          side: BorderSide(color: colors.outlineVariant),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(40),
          maximumSize: const Size.square(40),
          padding: const EdgeInsets.all(9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        highlightElevation: 0,
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 18),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        backgroundColor: colors.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: colors.onInverseSurface,
        ),
      ),
    );
  }
}
