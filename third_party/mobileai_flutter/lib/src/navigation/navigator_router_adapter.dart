import 'package:flutter/widgets.dart';

import '../core/types.dart';

class NavigatorRouterAdapter extends FlutterRouterAdapter implements RouteCatalogProvider {
  final GlobalKey<NavigatorState> navigatorKey;
  final List<String> availableScreens;
  final String Function()? currentScreenNameBuilder;
  final String? Function(String screen, {Object? params})? routeResolver;

  const NavigatorRouterAdapter({
    required this.navigatorKey,
    this.availableScreens = const [],
    this.currentScreenNameBuilder,
    this.routeResolver,
  });

  @override
  Future<void> back() async {
    navigatorKey.currentState?.maybePop();
  }

  @override
  List<String> getAvailableScreens() => availableScreens;

  @override
  List<String> getKnownRoutes() => availableScreens;

  @override
  String getCurrentScreenName() {
    if (currentScreenNameBuilder != null) {
      return currentScreenNameBuilder!();
    }
    return 'unknown';
  }

  @override
  Future<void> navigate(String screen, {Object? params}) async {
    final routeName = resolveRoute(screen, params: params) ?? screen;
    navigatorKey.currentState?.pushNamed(routeName, arguments: params);
  }

  @override
  Future<void> push(String href) async {
    navigatorKey.currentState?.pushNamed(href);
  }

  @override
  Future<void> replace(String href) async {
    navigatorKey.currentState?.pushReplacementNamed(href);
  }

  @override
  String? resolveRoute(String screen, {Object? params}) {
    if (routeResolver != null) {
      return routeResolver!(screen, params: params);
    }
    return screen.startsWith('/') ? screen : screen;
  }
}
