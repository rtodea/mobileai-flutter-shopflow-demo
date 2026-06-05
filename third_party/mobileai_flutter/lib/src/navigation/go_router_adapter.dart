import '../core/types.dart';

class GoRouterAdapter extends FlutterRouterAdapter implements RouteCatalogProvider {
  final dynamic router;
  final List<String> Function()? availableScreensBuilder;

  const GoRouterAdapter({
    required this.router,
    this.availableScreensBuilder,
  });

  @override
  Future<void> back() async {
    router.back();
  }

  @override
  List<String> getAvailableScreens() {
    if (availableScreensBuilder != null) {
      return availableScreensBuilder!();
    }
    return getKnownRoutes();
  }

  @override
  String getCurrentScreenName() {
    try {
      final topMatchedLocation = _readTopMatchedLocation();
      if (topMatchedLocation != null && topMatchedLocation.isNotEmpty) {
        return _canonicalizeLocation(topMatchedLocation);
      }

      final uri = router.routeInformationProvider.value.uri;
      return _canonicalizeLocation(uri.path);
    } catch (_) {
      return '/';
    }
  }

  String? _readTopMatchedLocation() {
    try {
      final dynamic topState = router.state;
      final matchedLocation = topState?.matchedLocation;
      if (matchedLocation is String && matchedLocation.isNotEmpty) {
        return matchedLocation;
      }
    } catch (_) {}

    try {
      final dynamic delegateState = router.routerDelegate?.state;
      final matchedLocation = delegateState?.matchedLocation;
      if (matchedLocation is String && matchedLocation.isNotEmpty) {
        return matchedLocation;
      }
    } catch (_) {}

    try {
      final dynamic currentConfiguration = router.routerDelegate?.currentConfiguration;
      final dynamic lastMatch = currentConfiguration?.last;
      final matchedLocation = lastMatch?.matchedLocation;
      if (matchedLocation is String && matchedLocation.isNotEmpty) {
        return matchedLocation;
      }
    } catch (_) {}

    return null;
  }

  @override
  List<String> getKnownRoutes() {
    try {
      return _collectRouteCatalog()
          .map((entry) => entry.path)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> navigate(String screen, {Object? params}) async {
    final route = resolveRoute(screen, params: params);
    if (route == null) return;
    router.go(route);
  }

  @override
  Future<void> push(String href) async {
    router.push(href);
  }

  @override
  Future<void> replace(String href) async {
    router.replace(href);
  }

  @override
  String? resolveRoute(String screen, {Object? params}) {
    final normalizedLookup = _normalizeLookup(screen);
    for (final entry in _collectRouteCatalog()) {
      if (entry.path == normalizedLookup || _routeAlias(entry.path) == normalizedLookup) {
        return entry.safeDirectNavigation ? entry.path : null;
      }
    }
    return null;
  }

  List<_RouteCatalogEntry> _collectRouteCatalog() {
    final entries = <String, _RouteCatalogEntry>{};
    for (final route in router.configuration.routes as List<dynamic>) {
      _collectRoutes(route, null, entries);
    }
    return entries.values.toList(growable: false);
  }

  void _collectRoutes(
    dynamic route,
    String? parentPath,
    Map<String, _RouteCatalogEntry> entries,
  ) {
    String? currentPath;

    try {
      final path = route.path as String?;
      if (path != null && path.isNotEmpty && path != '/') {
        currentPath = _joinRoutePath(parentPath, path);
        final resolvedPath = currentPath;
        entries.putIfAbsent(
          resolvedPath,
          () => _RouteCatalogEntry(
            path: resolvedPath,
            safeDirectNavigation: _isSafeDirectNavigation(resolvedPath),
          ),
        );
      }
    } catch (_) {
      currentPath = parentPath;
    }

    try {
      final children = route.routes as List<dynamic>?;
      if (children != null) {
        for (final child in children) {
          _collectRoutes(child, currentPath ?? parentPath, entries);
        }
      }
    } catch (_) {
      return;
    }
  }

  String _canonicalizeLocation(String location) {
    final normalizedLocation = _normalizePath(location);
    final catalog = List<_RouteCatalogEntry>.from(_collectRouteCatalog())
      ..sort((a, b) {
        final byLength = b.segments.length.compareTo(a.segments.length);
        if (byLength != 0) return byLength;
        return b.staticSegments.compareTo(a.staticSegments);
      });

    for (final entry in catalog) {
      if (_matchesPattern(entry.path, normalizedLocation)) {
        return entry.path;
      }
    }

    return normalizedLocation;
  }

  bool _matchesPattern(String pattern, String location) {
    final patternSegments = pattern.split('/').where((segment) => segment.isNotEmpty).toList();
    final locationSegments = location.split('/').where((segment) => segment.isNotEmpty).toList();
    if (patternSegments.length != locationSegments.length) {
      return false;
    }

    for (var index = 0; index < patternSegments.length; index += 1) {
      final patternSegment = patternSegments[index];
      final locationSegment = locationSegments[index];
      if (patternSegment.startsWith(':')) {
        continue;
      }
      if (patternSegment != locationSegment) {
        return false;
      }
    }

    return true;
  }

  String _normalizeLookup(String screen) {
    if (screen.startsWith('/')) {
      return _normalizePath(screen);
    }
    return '/${screen.trim()}';
  }

  String _joinRoutePath(String? parent, String child) {
    if (child.startsWith('/')) {
      return _normalizePath(child);
    }

    final parentPath = parent == null || parent.isEmpty || parent == '/'
        ? ''
        : _normalizePath(parent);
    final combined = '$parentPath/$child';
    return _normalizePath(combined);
  }

  String _normalizePath(String path) {
    final normalized = path.trim().replaceAll(RegExp(r'/+'), '/');
    if (normalized.isEmpty) return '/';
    if (!normalized.startsWith('/')) {
      return '/$normalized';
    }
    return normalized.endsWith('/') && normalized.length > 1
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  String _routeAlias(String path) {
    final segments = path.split('/').where((segment) => segment.isNotEmpty).toList();
    return segments.isEmpty ? '' : segments.last;
  }

  bool _isSafeDirectNavigation(String path) {
    final segments = path.split('/').where((segment) => segment.isNotEmpty).toList();
    return segments.length == 1 && segments.every((segment) => !segment.startsWith(':'));
  }
}

class _RouteCatalogEntry {
  final String path;
  final bool safeDirectNavigation;

  const _RouteCatalogEntry({
    required this.path,
    required this.safeDirectNavigation,
  });

  List<String> get segments => path.split('/').where((segment) => segment.isNotEmpty).toList();

  int get staticSegments => segments.where((segment) => !segment.startsWith(':')).length;
}
