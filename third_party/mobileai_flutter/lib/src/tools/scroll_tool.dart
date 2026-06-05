import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../core/types.dart';
import '../utils/logger.dart';
import '../widgets/highlight_overlay.dart';
import 'types.dart';

class ScrollTool implements AgentTool {
  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'scroll',
    description: 'Scroll the current screen to reveal more content.',
    effect: ToolEffect.navigate,
    parameters: {
      'direction': ToolParam(
        type: 'string',
        description: 'Direction to scroll',
        enumValues: ['down', 'up', 'left', 'right'],
      ),
      'amount': ToolParam(
        type: 'string',
        description: 'Amount to scroll',
        enumValues: ['page', 'toEnd', 'toStart'],
        required: false,
      ),
      'containerIndex': ToolParam(
        type: 'integer',
        description:
            'Optional index of a specific scrollable element (default: 0).',
        required: false,
      ),
    },
    handler: (args) => throw UnimplementedError(),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    final direction = args['direction'] as String?;
    final amount = args['amount'] as String? ?? 'page';
    final containerIndex = args['containerIndex'] as int? ?? 0;
    final hasExplicitContainerIndex =
        args.containsKey('containerIndex') && args['containerIndex'] != null;

    if (direction == null) {
      throw Exception('Missing required parameter: direction');
    }

    final scrollables = _canonicalScrollHosts(context.lastElements);
    final resolvedContainerIndex = _resolveContainerIndex(
      scrollables,
      requestedIndex: containerIndex,
      hasExplicitContainerIndex: hasExplicitContainerIndex,
      direction: direction,
    );

    Logger.info(
      '[ScrollTool] Attempting scroll direction=$direction amount=$amount '
      'containerIndex=${hasExplicitContainerIndex ? containerIndex : '(auto:$resolvedContainerIndex)'}',
    );
    Logger.debug(
      '[ScrollTool] Available scrollables: ${_summarizeElements(scrollables)}',
    );

    // Strategy 1: Dispatch via SemanticsAction on the scrollable node
    if (scrollables.isNotEmpty) {
      final targetScrollable = scrollables[resolvedContainerIndex];

      Logger.debug(
        '[ScrollTool] Target scrollable label=${targetScrollable.label} '
        'widget=${targetScrollable.element?.widget.runtimeType ?? 'none'} '
        'semanticsNodeId=${targetScrollable.semanticsNodeId}',
      );

      if (targetScrollable.semanticsNodeId != null) {
        final owner = RendererBinding.instance.rootPipelineOwner.semanticsOwner;
        if (owner != null) {
          try {
            SemanticsAction action;
            if (amount == 'toEnd') {
              action = direction == 'up' || direction == 'left'
                  ? SemanticsAction.scrollLeft
                  : SemanticsAction.scrollDown;
            } else if (amount == 'toStart') {
              action = direction == 'up' || direction == 'left'
                  ? SemanticsAction.scrollUp
                  : SemanticsAction.scrollLeft;
            } else {
              // page scroll
              action = switch (direction) {
                'down' => SemanticsAction.scrollDown,
                'up' => SemanticsAction.scrollUp,
                'left' => SemanticsAction.scrollLeft,
                _ => SemanticsAction.scrollRight,
              };
            }
            Logger.debug(
              '[ScrollTool] Performing semantics scroll action=$action '
              'on node=${targetScrollable.semanticsNodeId}',
            );
            owner.performAction(targetScrollable.semanticsNodeId!, action);
            _showFullScreenScrollGuide(direction, amount, context);
            return 'Scrolled $direction by $amount successfully.';
          } catch (e) {
            Logger.warn(
              'SemanticsAction scroll failed: $e — trying ScrollableState fallback',
            );
          }
        }
      }
    }

    // Strategy 2: Find ScrollableState from widget element reference
    Element? targetElement;
    if (scrollables.isNotEmpty) {
      final el = scrollables[resolvedContainerIndex].element;
      targetElement = el;
    }

    if (targetElement == null || !targetElement.mounted) {
      // Last resort: use a scrollable discovered from the root context subtree.
      Logger.warn(
        '[ScrollTool] Target element missing or unmounted. '
        'Trying root context scrollable from ${context.rootContext.widget.runtimeType}',
      );
      final scrollableState = _resolveRootScrollableState(
        context.rootContext,
        resolvedContainerIndex,
      );
      if (scrollableState == null) {
        final rootElement = context.rootContext is Element
            ? context.rootContext as Element
            : null;
        Logger.error(
          '[ScrollTool] No scrollable found on root context. '
          'rootPath=${rootElement != null ? _describeElementPath(rootElement) : context.rootContext.widget.runtimeType}',
        );
        throw Exception('No scrollable content found on this screen.');
      }
      return _scrollViaPosition(scrollableState.position, direction, amount);
    }

    Logger.debug(
      '[ScrollTool] Resolving ScrollableState from target path=${_describeElementPath(targetElement)}',
    );
    final scrollableState = _resolveScrollableState(
      targetElement,
      context.rootContext,
      resolvedContainerIndex,
    );
    if (scrollableState == null) {
      Logger.error(
        '[ScrollTool] Could not resolve ScrollableState. '
        'targetWidget=${targetElement.widget.runtimeType} '
        'targetPath=${_describeElementPath(targetElement)}',
      );
      throw Exception('Could not find ScrollableState for target element.');
    }

    return _scrollViaPosition(scrollableState.position, direction, amount);
  }

  ScrollableState? _resolveScrollableState(
    Element targetElement,
    BuildContext rootContext,
    int containerIndex,
  ) {
    final ownedState = _scrollableStateOwnedByElement(targetElement);
    if (ownedState != null) {
      Logger.debug(
        '[ScrollTool] Resolved ScrollableState from target-owned state: '
        '${ownedState.widget.runtimeType}',
      );
      return ownedState;
    }

    final contextualState =
        Scrollable.maybeOf(targetElement) ??
        targetElement.findAncestorStateOfType<ScrollableState>();
    if (contextualState != null) {
      Logger.debug(
        '[ScrollTool] Resolved ScrollableState from target context: '
        '${contextualState.widget.runtimeType}',
      );
      return contextualState;
    }

    final descendantState = _findDescendantScrollableState(targetElement);
    if (descendantState != null) {
      Logger.debug(
        '[ScrollTool] Resolved ScrollableState from descendant: '
        '${descendantState.widget.runtimeType}',
      );
      return descendantState;
    }

    return _resolveRootScrollableState(rootContext, containerIndex);
  }

  int _resolveContainerIndex(
    List<InteractiveElement> scrollables, {
    required int requestedIndex,
    required bool hasExplicitContainerIndex,
    required String direction,
  }) {
    if (scrollables.isEmpty) {
      return 0;
    }

    if (hasExplicitContainerIndex) {
      return requestedIndex.clamp(0, scrollables.length - 1);
    }

    final preferredOrientation = direction == 'left' || direction == 'right'
        ? 'horizontal'
        : 'vertical';
    final preferredIndex = scrollables.indexWhere(
      (scrollable) =>
          scrollable.properties['orientation'] == preferredOrientation,
    );
    if (preferredIndex >= 0) {
      return preferredIndex;
    }
    return 0;
  }

  List<InteractiveElement> _canonicalScrollHosts(
    List<InteractiveElement> elements,
  ) {
    final canonical = <InteractiveElement>[];
    final seen = <String>{};

    for (final element in elements) {
      if (element.type != ElementType.scrollable) {
        continue;
      }
      final hostId =
          element.properties['scrollHostId']?.toString() ??
          element.properties['id']?.toString() ??
          'element:${identityHashCode(element.element)}:${element.index}';
      if (seen.add(hostId)) {
        canonical.add(element);
      }
    }

    return canonical;
  }

  ScrollableState? _resolveRootScrollableState(
    BuildContext rootContext,
    int containerIndex,
  ) {
    final directState = Scrollable.maybeOf(rootContext);
    if (directState != null) {
      Logger.debug(
        '[ScrollTool] Resolved root ScrollableState from context: '
        '${directState.widget.runtimeType}',
      );
      return directState;
    }

    final rootElement = rootContext is Element ? rootContext : null;
    if (rootElement == null || !rootElement.mounted) {
      return null;
    }

    final discoveredStates = _findOwnedScrollableStates(rootElement);
    if (discoveredStates.isEmpty) {
      return null;
    }

    final clampedIndex = containerIndex.clamp(0, discoveredStates.length - 1);
    final resolved = discoveredStates[clampedIndex];
    Logger.debug(
      '[ScrollTool] Resolved root ScrollableState from subtree index=$clampedIndex '
      'widget=${resolved.widget.runtimeType}',
    );
    return resolved;
  }

  ScrollableState? _scrollableStateOwnedByElement(Element element) {
    if (element is StatefulElement && element.state is ScrollableState) {
      return element.state as ScrollableState;
    }
    return null;
  }

  ScrollableState? _findDescendantScrollableState(Element root) {
    final queue = <Element>[root];
    final visited = <Element>{};

    while (queue.isNotEmpty && visited.length < 800) {
      final element = queue.removeAt(0);
      if (!visited.add(element) || !element.mounted) {
        continue;
      }

      final ownedState = _scrollableStateOwnedByElement(element);
      if (ownedState != null) {
        return ownedState;
      }

      element.visitChildElements(queue.add);
    }

    return null;
  }

  List<ScrollableState> _findOwnedScrollableStates(Element root) {
    final results = <ScrollableState>[];
    final seenStates = <ScrollableState>{};
    final queue = <Element>[root];
    final visited = <Element>{};

    while (queue.isNotEmpty && visited.length < 2000) {
      final element = queue.removeAt(0);
      if (!visited.add(element) || !element.mounted) {
        continue;
      }

      final ownedState = _scrollableStateOwnedByElement(element);
      if (ownedState != null && seenStates.add(ownedState)) {
        results.add(ownedState);
      }

      element.visitChildElements(queue.add);
    }

    return results;
  }

  Future<String> _scrollViaPosition(
    ScrollPosition pos,
    String direction,
    String amount,
  ) async {
    Logger.debug(
      '[ScrollTool] Scroll position before move: pixels=${pos.pixels}, '
      'min=${pos.minScrollExtent}, max=${pos.maxScrollExtent}, viewport=${pos.viewportDimension}',
    );
    double targetOffset = pos.pixels;
    final viewportDimension = pos.viewportDimension;
    final isReverse = direction == 'up' || direction == 'left';
    final sign = isReverse ? -1 : 1;

    if (amount == 'page') {
      targetOffset += sign * viewportDimension * 0.8;
    } else if (amount == 'toEnd') {
      targetOffset = pos.maxScrollExtent;
    } else if (amount == 'toStart') {
      targetOffset = pos.minScrollExtent;
    }

    targetOffset = targetOffset.clamp(pos.minScrollExtent, pos.maxScrollExtent);

    if ((targetOffset - pos.pixels).abs() < 1.0) {
      return 'Already at the $direction edge of the scrollable area.';
    }

    await pos.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    await Future.delayed(const Duration(milliseconds: 100));
    Logger.debug(
      '[ScrollTool] Scroll position after move: pixels=${pos.pixels}, target=$targetOffset',
    );
    _showFullScreenScrollGuideFromPosition(direction, amount, pos);
    return 'Scrolled $direction by $amount successfully.';
  }

  String _summarizeElements(List<InteractiveElement> elements) {
    if (elements.isEmpty) {
      return '(none)';
    }
    return elements
        .map(
          (element) =>
              '[${element.index}] ${element.label} (${element.type.name})',
        )
        .join(' | ');
  }

  void _showFullScreenScrollGuide(
    String direction,
    String amount,
    ToolContext context,
  ) {
    final size = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    const inset = 8.0;
    HighlightController.show(HighlightEventData(
      pageX: inset,
      pageY: inset,
      width: size.width - inset * 2,
      height: size.height - inset * 2,
      action: HighlightAction.scroll,
      message: 'Scrolled $direction${amount != 'page' ? ' to $amount' : ''}',
      autoRemoveAfterMs: 3000,
      borderOnly: true,
    ));
  }

  void _showFullScreenScrollGuideFromPosition(
    String direction,
    String amount,
    ScrollPosition pos,
  ) {
    final size = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    const inset = 8.0;
    HighlightController.show(HighlightEventData(
      pageX: inset,
      pageY: inset,
      width: size.width - inset * 2,
      height: size.height - inset * 2,
      action: HighlightAction.scroll,
      message: 'Scrolled $direction${amount != 'page' ? ' to $amount' : ''}',
      autoRemoveAfterMs: 3000,
      borderOnly: true,
    ));
  }

  String _describeElementPath(Element element, {int maxAncestors = 12}) {
    final path = <String>[element.widget.runtimeType.toString()];
    var count = 0;
    element.visitAncestorElements((ancestor) {
      if (count >= maxAncestors) return false;
      path.add(ancestor.widget.runtimeType.toString());
      count += 1;
      return true;
    });
    return path.join(' <- ');
  }
}
