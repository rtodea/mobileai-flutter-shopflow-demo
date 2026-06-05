import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'element_tree_walker.dart';
import 'screen_dehydrator.dart';
import 'types.dart';
import 'zone_registry.dart';
import '../utils/logger.dart';

class FlutterPlatformAdapter implements PlatformAdapter {
  final AgentConfig config;
  final GlobalKey rootKey;
  final GlobalKey<NavigatorState>? navigatorKey;
  final String Function() getCurrentScreenName;
  final List<String> Function() getRouteNames;

  const FlutterPlatformAdapter({
    required this.config,
    required this.rootKey,
    required this.getCurrentScreenName,
    required this.getRouteNames,
    this.navigatorKey,
  });

  @override
  Future<ScreenSnapshot> getScreenSnapshot() async {
    final rootContext = rootKey.currentContext;
    Logger.info(
      '[FlutterPlatformAdapter] Creating screen snapshot. '
      'root=${rootContext?.widget.runtimeType ?? 'null'}, '
      'screen=${getCurrentScreenName()}',
    );
    final walker = ElementTreeWalker(config);
    final interactives = walker.walk(rootKey.currentContext!);
    var elementsText = ScreenDehydrator.dehydrate(interactives);
    if (config.transformScreenContent != null) {
      elementsText = await config.transformScreenContent!(elementsText);
    }

    final zones = globalZoneRegistry
        .getAll()
        .map(
          (zone) => ZoneSnapshot(
            id: zone.config.id,
            allowInjectBlock:
                zone.config.allowInjectBlock || zone.config.allowInjectCard,
            interventionEligible: zone.config.interventionEligible,
            proactiveIntervention: zone.config.proactiveIntervention,
            blockNames: zone.config.blocks
                .map((block) => block.name)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);

    Logger.info(
      '[FlutterPlatformAdapter] Snapshot complete. '
      'screen=${getCurrentScreenName()}, count=${interactives.length}, '
      'sample=${_summarizeInteractiveElements(interactives)}',
    );

    return ScreenSnapshot(
      screenName: getCurrentScreenName(),
      availableScreens: getRouteNames(),
      elementsText: elementsText,
      elements: interactives,
      zones: zones,
    );
  }

  @override
  NavigationSnapshot getNavigationSnapshot() {
    return NavigationSnapshot(
      currentScreenName: getCurrentScreenName(),
      availableScreens: getRouteNames(),
    );
  }

  @override
  Future<String> executeAction(ActionIntent intent) async {
    if (intent.action == 'navigate') {
      final screen = intent.args['screen']?.toString();
      if (screen == null || screen.isEmpty) {
        return 'Missing screen name.';
      }

      final normalizedScreen = _normalizeScreenKey(screen);
      if (!_canNavigateDirectly(normalizedScreen)) {
        return 'Direct navigation to $normalizedScreen is not allowed. Reach it by tapping through the UI.';
      }

      if (config.routerAdapter != null) {
        await config.routerAdapter!.navigate(
          normalizedScreen,
          params: intent.args['params'],
        );
        return 'Navigated to $normalizedScreen.';
      }

      if (config.router != null) {
        config.router!.go(normalizedScreen);
        return 'Navigated to $normalizedScreen.';
      }

      navigatorKey?.currentState?.pushNamed(
        normalizedScreen,
        arguments: intent.args['params'],
      );
      return 'Navigated to $normalizedScreen.';
    }

    if (intent.action == 'wait') {
      final seconds = (intent.args['seconds'] as num?)?.toInt() ?? 2;
      await Future<void>.delayed(Duration(seconds: seconds));
      return 'Waited $seconds seconds.';
    }

    return 'Unsupported platform action: ${intent.action}';
  }

  String _normalizeScreenKey(String screen) {
    if (screen.startsWith('/')) return screen;
    return '/$screen';
  }

  bool _canNavigateDirectly(String screen) {
    final mapEntry = config.screenMap?.screens[screen];
    if (mapEntry != null) {
      if (mapEntry.safeDirectNavigation != null) {
        return mapEntry.safeDirectNavigation!;
      }
      final segments = screen
          .split('/')
          .where((segment) => segment.isNotEmpty)
          .toList();
      return segments.length == 1 &&
          segments.every((segment) => !segment.startsWith(':'));
    }

    final resolved = config.routerAdapter?.resolveRoute(screen);
    if (resolved == null) {
      return false;
    }
    final segments = resolved
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    return segments.length == 1 &&
        segments.every((segment) => !segment.startsWith(':'));
  }

  /// Captures the widget tree rooted at [rootKey] as a compressed JPEG
  /// encoded in base64. Returns null if the root has not been laid out yet
  /// or if the render object is not a [RenderRepaintBoundary].
  @override
  Future<String?> captureScreenshot() async {
    try {
      final renderObject = rootKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) return null;
      final image = await renderObject.toImage(pixelRatio: 0.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return base64Encode(byteData.buffer.asUint8List());
    } catch (e) {
      Logger.warn('[FlutterPlatformAdapter] captureScreenshot failed: $e');
      return null;
    }
  }

  String _summarizeInteractiveElements(
    List<InteractiveElement> elements, {
    int limit = 8,
  }) {
    if (elements.isEmpty) {
      return '(none)';
    }
    return elements
        .take(limit)
        .map(
          (element) =>
              '[${element.index}] ${element.label} (${element.type.name})',
        )
        .join(' | ');
  }
}
