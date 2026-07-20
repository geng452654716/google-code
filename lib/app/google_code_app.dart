import 'package:flutter/material.dart';

import 'navigation/root_route_observer.dart';
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

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark
          ? ThemeMode.light
          : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xff3157d5);
    final inputTheme = InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_routeObserver],
      title: 'TOTP Vault',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xfff7f8fc),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: inputTheme,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff111318),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: inputTheme,
        useMaterial3: true,
      ),
      home: VaultGate(
        onToggleTheme: _toggleTheme,
        onClearSensitiveRoutes: _routeObserver.removeAllAboveRoot,
      ),
    );
  }
}
