import 'package:flutter/material.dart';

import 'navigation/root_route_observer.dart';
import 'theme/totp_vault_theme.dart';
import 'vault_gate.dart';

/// Root application widget and global theme owner.
class GoogleCodeApp extends StatefulWidget {
  const GoogleCodeApp({super.key});

  @override
  State<GoogleCodeApp> createState() => _GoogleCodeAppState();
}

class _GoogleCodeAppState extends State<GoogleCodeApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _routeObserver = RootRouteObserver();
  ThemeMode _themeMode = ThemeMode.system;

  /// Toggles from the effective system brightness on the first interaction.
  void _toggleTheme() {
    final isCurrentlyDark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    setState(() {
      _themeMode = isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_routeObserver],
      title: 'TOTP Vault',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: TotpVaultTheme.light(),
      darkTheme: TotpVaultTheme.dark(),
      home: VaultGate(
        onToggleTheme: _toggleTheme,
        onClearSensitiveRoutes: _routeObserver.removeAllAboveRoot,
      ),
    );
  }
}
