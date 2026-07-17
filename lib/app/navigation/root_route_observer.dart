import 'package:flutter/widgets.dart';

/// Tracks root navigator routes so security locks can remove modals instantly.
class RootRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _routes[index] = newRoute;
    } else {
      if (oldRoute != null) _routes.remove(oldRoute);
      if (newRoute != null) _routes.add(newRoute);
    }
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  /// Removes dialogs and pushed pages without waiting for exit animations.
  void removeAllAboveRoot() {
    final activeNavigator = navigator;
    if (activeNavigator == null || _routes.length <= 1) return;
    final routesToRemove = _routes.skip(1).toList(growable: false).reversed;
    for (final route in routesToRemove) {
      if (_routes.contains(route)) activeNavigator.removeRoute(route);
    }
  }
}
