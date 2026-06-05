import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'types.dart';
import '../utils/logger.dart';

/// ElementTreeWalker — discovers interactive widgets and meaningful labels from
/// the host app widget tree.
///
/// The widget tree is the primary source of truth. Semantics is only used as an
/// optional fallback when widget extraction fails entirely.
class ElementTreeWalker {
  final AgentConfig config;
  static const int _maxWidgetVisits = 6000;
  static const int _maxSemanticsDepth = 32;

  ElementTreeWalker(this.config);

  List<InteractiveElement> walk(dynamic rootContext) {
    final primaryRoot = rootContext is Element && rootContext.mounted ? rootContext : null;

    if (primaryRoot != null) {
      final widgetResults = _walkWidgetTree(primaryRoot);
      if (widgetResults.isNotEmpty) {
        Logger.info(
          '[ElementTreeWalker] Primary root succeeded. '
          'root=${primaryRoot.widget.runtimeType}, count=${widgetResults.length}, '
          'sample=${_summarizeElements(widgetResults)}',
        );
        return widgetResults;
      }
      Logger.warn(
        '[ElementTreeWalker] Primary root was empty. '
        'root=${primaryRoot.widget.runtimeType}, '
        'path=${_describeElementPath(primaryRoot)}, '
        'children=${_describeChildWidgets(primaryRoot)}',
      );
    }

    final globalRoot = WidgetsBinding.instance.rootElement;
    if (primaryRoot == null && globalRoot != null) {
      final widgetResults = _walkWidgetTree(globalRoot);
      if (widgetResults.isNotEmpty) {
        Logger.info(
          '[ElementTreeWalker] Global root succeeded. '
          'root=${globalRoot.widget.runtimeType}, count=${widgetResults.length}, '
          'sample=${_summarizeElements(widgetResults)}',
        );
        return widgetResults;
      }
      Logger.warn(
        '[ElementTreeWalker] Global root was empty. '
        'root=${globalRoot.widget.runtimeType}, '
        'path=${_describeElementPath(globalRoot)}, '
        'children=${_describeChildWidgets(globalRoot)}',
      );
    }

    final semanticsResults = _walkSemanticsTree();
    Logger.warn(
      '[ElementTreeWalker] Falling back to semantics. '
      'count=${semanticsResults.length}, sample=${_summarizeElements(semanticsResults)}',
    );
    return semanticsResults;
  }

  List<InteractiveElement> _walkWidgetTree(Element root) {
    final results = <InteractiveElement>[];
    final emittedKeys = <String>{};
    final counter = _Counter(1);
    var visitedCount = 0;
    var maxDepthReached = 0;
    var hitVisitBudget = false;
    final visitSamples = <String>[];
    final interestingCounts = <String, int>{};
    final descriptorSamples = <String>[];

    void visit(Element element, int depth) {
      if (!element.mounted) {
        return;
      }
      if (visitedCount > _maxWidgetVisits) {
        hitVisitBudget = true;
        return;
      }
      visitedCount += 1;
      if (depth > maxDepthReached) {
        maxDepthReached = depth;
      }

      final widget = element.widget;
      if (_isHiddenElement(element)) {
        return;
      }
      final widgetType = widget.runtimeType.toString();
      if (visitSamples.length < 80) {
        visitSamples.add('$depth:$widgetType');
      }
      if (_isTraceWidget(widget)) {
        interestingCounts.update(widgetType, (value) => value + 1, ifAbsent: () => 1);
        if (descriptorSamples.length < 48) {
          final descriptor = _detectInteractiveCandidate(element);
          final descriptorType = descriptor?.type.name ?? 'none';
          final descriptorLabel = descriptor == null
              ? ''
              : _normalizeText(_resolveCandidateLabel(element, descriptor));
          final collectedLabel = _normalizeText(
            _collectLabelFromElement(element, maxDepth: 3),
          );
          descriptorSamples.add(
            '$depth:$widgetType:descriptor=$descriptorType:label=$descriptorLabel:collected=$collectedLabel',
          );
        }
      }
      final ignoredWidget = _isIgnoredWidget(widget);
      if (ignoredWidget && _shouldPruneIgnoredSubtree(widget)) {
        return;
      }

      if (!ignoredWidget) {
        _emitWidgetElements(
          element,
          results,
          emittedKeys,
          counter,
        );
        if (_shouldPruneInteractiveSubtree(widget)) {
          return;
        }
      }

      element.visitChildElements((child) => visit(child, depth + 1));
    }

    visit(root, 0);
    if (results.isEmpty) {
      Logger.warn(
        '[ElementTreeWalker] Widget walk found no interactives. '
        'root=${root.widget.runtimeType}, visited=$visitedCount, '
        'maxDepth=$maxDepthReached, hitVisitBudget=$hitVisitBudget, '
        'samples=${visitSamples.join(' | ')}',
      );
      Logger.warn(
        '[ElementTreeWalker] Trace counts for ${root.widget.runtimeType}: '
        '${interestingCounts.entries.map((entry) => '${entry.key}=${entry.value}').join(', ')}',
      );
      if (descriptorSamples.isNotEmpty) {
        Logger.warn(
          '[ElementTreeWalker] Trace samples for ${root.widget.runtimeType}: '
          '${descriptorSamples.join(' | ')}',
        );
      }
    }
    return results;
  }

  void _emitWidgetElements(
    Element element,
    List<InteractiveElement> results,
    Set<String> emittedKeys,
    _Counter counter,
  ) {
    final widget = element.widget;

    if (widget is BottomNavigationBar && widget.onTap != null) {
      for (var index = 0; index < widget.items.length; index += 1) {
        final item = widget.items[index];
        final label = _firstNonEmpty([
          item.label,
          _describeIconData(_iconDataFromWidget(item.icon)),
        ]);
        _appendElement(
          results,
          emittedKeys,
          counter,
          element: element,
          label: label,
          type: ElementType.pressable,
          properties: {
            'actionIndex': index,
            'selected': widget.currentIndex == index,
            'enabled': true,
            'role': 'tab',
          },
        );
      }
      return;
    }

    if (widget is NavigationBar && widget.onDestinationSelected != null) {
      for (var index = 0; index < widget.destinations.length; index += 1) {
        final destination = widget.destinations[index];
        final label = _navigationDestinationLabel(destination);
        _appendElement(
          results,
          emittedKeys,
          counter,
          element: element,
          label: label,
          type: ElementType.pressable,
          properties: {
            'actionIndex': index,
            'selected': widget.selectedIndex == index,
            'enabled': true,
            'role': 'tab',
          },
        );
      }
      return;
    }

    if (widget is TabBar) {
      for (var index = 0; index < widget.tabs.length; index += 1) {
        final tab = widget.tabs[index];
        final label = _tabLabel(tab);
        _appendElement(
          results,
          emittedKeys,
          counter,
          element: element,
          label: label,
          type: ElementType.pressable,
          properties: {
            'actionIndex': index,
            'selected': widget.controller?.index == index,
            'enabled': true,
            'role': 'tab',
          },
        );
      }
      return;
    }

    final candidate = _detectInteractiveCandidate(element);
    if (candidate != null) {
      _appendElement(
        results,
        emittedKeys,
        counter,
        element: element,
        label: _resolveCandidateLabel(element, candidate),
        type: candidate.type,
        properties: candidate.properties,
      );
      return;
    }

    if (_shouldEmitTextElement(element)) {
      final label = _extractTextFromWidget(element.widget);
      _appendElement(
        results,
        emittedKeys,
        counter,
        element: element,
        label: label,
        type: ElementType.text,
      );
    }
  }

  _InteractiveCandidate? _detectInteractiveCandidate(Element element) {
    final widget = element.widget;

    if (widget is SwitchListTile) {
      return _InteractiveCandidate(
        type: ElementType.switchToggle,
        explicitLabels: [
          _extractTextFromWidget(widget.title),
          _extractTextFromWidget(widget.subtitle),
        ],
        genericFallback: 'Switch',
        properties: _stateProperties(
          role: 'switch',
          value: widget.value,
          checked: widget.value,
          enabled: widget.onChanged != null,
        ),
      );
    }

    if (widget is CheckboxListTile) {
      return _InteractiveCandidate(
        type: ElementType.checkbox,
        explicitLabels: [
          _extractTextFromWidget(widget.title),
          _extractTextFromWidget(widget.subtitle),
        ],
        genericFallback: 'Checkbox',
        properties: _stateProperties(
          role: 'checkbox',
          checked: widget.value,
          enabled: widget.onChanged != null,
        ),
      );
    }

    if (widget is ListTile && (widget.onTap != null || widget.onLongPress != null)) {
      return _InteractiveCandidate(
        type: ElementType.pressable,
        explicitLabels: [
          _extractTextFromWidget(widget.title),
          _extractTextFromWidget(widget.subtitle),
          _extractTextFromWidget(widget.trailing),
        ],
        genericFallback: 'Button',
        properties: _stateProperties(
          role: 'button',
          selected: widget.selected ? true : null,
          enabled: widget.enabled,
        ),
      );
    }

    if (widget is ButtonStyleButton) {
      return _InteractiveCandidate(
        type: ElementType.pressable,
        explicitLabels: [
          _extractTextFromWidget(widget.child),
        ],
        genericFallback: 'Button',
        properties: _stateProperties(
          role: 'button',
          enabled: widget.onPressed != null,
        ),
      );
    }

    if (widget is IconButton) {
      return _InteractiveCandidate(
        type: ElementType.pressable,
        explicitLabels: [
          widget.tooltip,
        ],
        iconFallback: _describeIconData(_iconDataFromWidget(widget.icon)),
        genericFallback: 'Icon Button',
        properties: _stateProperties(
          role: 'button',
          selected: widget.isSelected,
          enabled: widget.onPressed != null,
        ),
      );
    }

    if (widget is FloatingActionButton) {
      return _InteractiveCandidate(
        type: ElementType.pressable,
        explicitLabels: [
          widget.tooltip,
          _extractTextFromWidget(widget.child),
        ],
        iconFallback: _describeIconData(_iconDataFromWidget(widget.child)),
        genericFallback: 'Floating Action Button',
        properties: _stateProperties(
          role: 'button',
          enabled: widget.onPressed != null,
        ),
      );
    }

    if (widget is InkWell && widget.onTap != null) {
      return const _InteractiveCandidate(
        type: ElementType.pressable,
        properties: <String, dynamic>{'role': 'button', 'enabled': true},
        genericFallback: 'Button',
      );
    }

    if (widget is GestureDetector && widget.onTap != null) {
      return const _InteractiveCandidate(
        type: ElementType.pressable,
        properties: <String, dynamic>{'role': 'button', 'enabled': true},
        genericFallback: 'Button',
      );
    }

    if (widget is FilterChip) {
      return _InteractiveCandidate(
        type: ElementType.pressable,
        explicitLabels: [
          _extractTextFromWidget(widget.label),
        ],
        genericFallback: 'Filter',
        properties: _stateProperties(
          role: 'button',
          selected: widget.selected,
          enabled: widget.onSelected != null,
        ),
      );
    }

    if (widget is ChoiceChip) {
      return _InteractiveCandidate(
        type: ElementType.pressable,
        explicitLabels: [
          _extractTextFromWidget(widget.label),
        ],
        genericFallback: 'Choice',
        properties: _stateProperties(
          role: 'button',
          selected: widget.selected,
          enabled: widget.onSelected != null,
        ),
      );
    }

    if (widget is ActionChip) {
      return _InteractiveCandidate(
        type: ElementType.pressable,
        explicitLabels: [
          _extractTextFromWidget(widget.label),
        ],
        genericFallback: 'Action',
        properties: _stateProperties(
          role: 'button',
          enabled: widget.onPressed != null,
        ),
      );
    }

    if (widget is InputChip) {
      return _InteractiveCandidate(
        type: ElementType.pressable,
        explicitLabels: [
          _extractTextFromWidget(widget.label),
        ],
        genericFallback: 'Chip',
        properties: _stateProperties(
          role: 'button',
          selected: widget.selected ? true : null,
          enabled: widget.onPressed != null || widget.onSelected != null,
        ),
      );
    }

    if (widget is Switch) {
      return _InteractiveCandidate(
        type: ElementType.switchToggle,
        genericFallback: 'Switch',
        properties: _stateProperties(
          role: 'switch',
          value: widget.value,
          checked: widget.value,
          enabled: widget.onChanged != null,
        ),
      );
    }

    if (widget is Checkbox) {
      return _InteractiveCandidate(
        type: ElementType.checkbox,
        genericFallback: 'Checkbox',
        properties: _stateProperties(
          role: 'checkbox',
          checked: widget.value ?? false,
          enabled: widget.onChanged != null,
        ),
      );
    }

    if (widget is Slider) {
      return _InteractiveCandidate(
        type: ElementType.slider,
        explicitLabels: [
          widget.label,
        ],
        genericFallback: 'Slider',
        properties: _stateProperties(
          role: 'slider',
          value: widget.value,
          enabled: widget.onChanged != null,
        ),
      );
    }

    if (widget is TextField) {
      final currentValue = widget.controller?.text;
      return _InteractiveCandidate(
        type: ElementType.textInput,
        explicitLabels: [
          widget.decoration?.labelText,
          widget.decoration?.hintText,
        ],
        genericFallback: 'Text Field',
        properties: _stateProperties(
          role: 'textbox',
          value: currentValue != null && currentValue.isNotEmpty ? currentValue : null,
          hint: widget.decoration?.hintText,
          placeholder: widget.decoration?.hintText,
          enabled: widget.enabled != false,
        ),
      );
    }

    if (widget is TextFormField) {
      final decoration = _readInputDecoration(widget);
      final value = _readTextFormFieldValue(widget);
      return _InteractiveCandidate(
        type: ElementType.textInput,
        explicitLabels: [
          decoration?.labelText,
          decoration?.hintText,
        ],
        genericFallback: 'Text Field',
        properties: _stateProperties(
          role: 'textbox',
          value: value,
          hint: decoration?.hintText,
          placeholder: decoration?.hintText,
          enabled: _readInputEnabled(widget),
        ),
      );
    }

    if (widget is DropdownButton) {
      return _InteractiveCandidate(
        type: ElementType.picker,
        explicitLabels: [
          _extractTextFromWidget(widget.hint),
        ],
        genericFallback: 'Picker',
        properties: _stateProperties(
          role: 'combobox',
          value: widget.value?.toString(),
          hint: _extractTextFromWidget(widget.hint),
          enabled: widget.onChanged != null,
        ),
      );
    }

    if (widget is DropdownButtonFormField) {
      return _InteractiveCandidate(
        type: ElementType.picker,
        explicitLabels: [
          widget.decoration.labelText,
          widget.decoration.hintText,
        ],
        genericFallback: 'Picker',
        properties: _stateProperties(
          role: 'combobox',
          value: widget.initialValue?.toString(),
          hint: widget.decoration.hintText,
          placeholder: widget.decoration.hintText,
          enabled: widget.onChanged != null,
        ),
      );
    }

    if (widget is Radio) {
      final dynamic dynamicWidget = widget;
      return _InteractiveCandidate(
        type: ElementType.pressable,
        genericFallback: 'Radio',
        properties: _stateProperties(
          role: 'radio',
          checked: dynamicWidget.groupValue == dynamicWidget.value,
          selected: dynamicWidget.groupValue == dynamicWidget.value,
          value: dynamicWidget.value?.toString(),
          enabled: dynamicWidget.onChanged != null,
        ),
      );
    }

    if (widget is RadioListTile) {
      final dynamic dynamicWidget = widget;
      return _InteractiveCandidate(
        type: ElementType.pressable,
        explicitLabels: [
          _extractTextFromWidget(dynamicWidget.title as Widget?),
          _extractTextFromWidget(dynamicWidget.subtitle as Widget?),
        ],
        genericFallback: 'Radio',
        properties: _stateProperties(
          role: 'radio',
          checked: dynamicWidget.groupValue == dynamicWidget.value,
          selected: dynamicWidget.groupValue == dynamicWidget.value,
          value: dynamicWidget.value?.toString(),
          enabled: dynamicWidget.onChanged != null,
        ),
      );
    }

    if ((widget is ScrollView || widget is Scrollable || widget is PageView) &&
        _isCanonicalScrollHost(element)) {
      final orientation = _describeScrollOrientation(widget);
      return _InteractiveCandidate(
        type: ElementType.scrollable,
        properties: _stateProperties(
          role: 'scrollable',
          enabled: true,
          orientation: orientation,
        ),
        genericFallback: _scrollableFallbackLabel(orientation),
        allowDeepLabel: false,
      );
    }

    final widgetType = widget.runtimeType.toString();
    if (widgetType.contains('CupertinoButton')) {
      return const _InteractiveCandidate(
        type: ElementType.pressable,
        properties: <String, dynamic>{'role': 'button', 'enabled': true},
        genericFallback: 'Button',
      );
    }

    if (widgetType.contains('CupertinoSwitch')) {
      return const _InteractiveCandidate(
        type: ElementType.switchToggle,
        properties: <String, dynamic>{'role': 'switch', 'enabled': true},
        genericFallback: 'Switch',
      );
    }

    if (widgetType.contains('CupertinoTextField')) {
      return const _InteractiveCandidate(
        type: ElementType.textInput,
        properties: <String, dynamic>{'role': 'textbox', 'enabled': true},
        genericFallback: 'Text Field',
      );
    }

    return null;
  }

  String _resolveCandidateLabel(Element element, _InteractiveCandidate candidate) {
    final explicitLabel = _composeLabel(candidate.explicitLabels);
    final tooltipLabel = _resolveTooltipForElement(element);
    final directClusterLabel = candidate.allowDeepLabel
        ? _bestClusterLabel(
            _collectLabelClusters(element, maxDepth: 10, includeRoot: false),
          )
        : '';
    final deepClusterLabel = candidate.allowDeepLabel
        ? _bestClusterLabel(
            _collectLabelClusters(element, maxDepth: 16, includeRoot: true),
          )
        : '';
    final nearbyLabel = candidate.allowDeepLabel ? _findNearbyLabel(element) : '';

    Logger.debug(
      '[ElementTreeWalker] Candidate label resolution '
      'widget=${element.widget.runtimeType} '
      'explicit=${explicitLabel.isEmpty ? '(empty)' : explicitLabel} '
      'tooltip=${tooltipLabel.isEmpty ? '(empty)' : tooltipLabel} '
      'direct=${directClusterLabel.isEmpty ? '(empty)' : directClusterLabel} '
      'deep=${deepClusterLabel.isEmpty ? '(empty)' : deepClusterLabel} '
      'nearby=${nearbyLabel.isEmpty ? '(empty)' : nearbyLabel} '
      'icon=${candidate.iconFallback.isEmpty ? '(empty)' : candidate.iconFallback} '
      'fallback=${candidate.genericFallback.isEmpty ? '(empty)' : candidate.genericFallback}',
    );

    return _firstNonEmpty([
      explicitLabel,
      tooltipLabel,
      directClusterLabel,
      deepClusterLabel,
      nearbyLabel,
      candidate.iconFallback,
      candidate.genericFallback,
    ]);
  }

  void _appendElement(
    List<InteractiveElement> results,
    Set<String> emittedKeys,
    _Counter counter, {
    required Element element,
    required String label,
    required ElementType type,
    Map<String, dynamic> properties = const <String, dynamic>{},
  }) {
    final normalizedLabel = _normalizeText(label);
    if (normalizedLabel.isEmpty) {
      return;
    }

    final canonicalProperties = _canonicalizeProperties(element, type, properties);
    final dedupeKey =
        '${canonicalProperties['id'] ?? identityHashCode(element)}|'
        '${type.name}|$normalizedLabel|${canonicalProperties['actionIndex'] ?? ''}';
    if (!emittedKeys.add(dedupeKey)) {
      return;
    }

    results.add(
      InteractiveElement(
        index: counter.value,
        label: normalizedLabel,
        type: type,
        element: element,
        semanticsNodeId: null,
        properties: canonicalProperties,
      ),
    );
    counter.value += 1;
  }

  bool _shouldEmitTextElement(Element element) {
    if (element.widget is! Text && element.widget is! RichText) {
      return false;
    }
    if (element.widget is RichText) {
      var textAncestorFound = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is Text) {
          textAncestorFound = true;
          return false;
        }
        return true;
      });
      if (textAncestorFound) {
        return false;
      }
    }
    final label = _extractTextFromWidget(element.widget);
    if (!_isMeaningfulText(label)) {
      return false;
    }
    if (_hasEquivalentInteractiveAncestorLabel(element, label)) {
      return false;
    }
    return true;
  }

  bool _subtreeContains(Element root, Element target) {
    if (identical(root, target)) return true;
    var contains = false;
    root.visitChildElements((child) {
      if (_subtreeContains(child, target)) {
        contains = true;
      }
    });
    return contains;
  }

  String _findNearbyLabel(Element element) {
    final labels = <String>[];
    var ancestorCount = 0;

    element.visitAncestorElements((ancestor) {
      if (ancestorCount >= 3 || labels.isNotEmpty) {
        return true;
      }
      ancestorCount += 1;
      ancestor.visitChildElements((child) {
        if (_subtreeContains(child, element)) {
          return;
        }
        if (_isIgnoredWidget(child.widget) || _isHiddenElement(child)) {
          return;
        }
        final text = _firstNonEmpty([
          _bestClusterLabel(
            _collectLabelClusters(child, maxDepth: 3, includeRoot: true),
          ),
          _collectLabelFromElement(child, maxDepth: 2),
        ]);
        if (_isMeaningfulText(text) && !labels.contains(text)) {
          labels.add(text);
        }
      });
      if (labels.isEmpty) {
        final ownText = _extractTextFromWidget(ancestor.widget);
        if (_isMeaningfulText(ownText)) {
          labels.add(ownText);
        }
      }
      return labels.isEmpty;
    });

    return _composeLabel(labels);
  }

  String _collectLabelFromElement(Element element, {int maxDepth = 4}) {
    if (_isIgnoredWidget(element.widget) || _isHiddenElement(element)) {
      return '';
    }

    final clusteredLabel = _bestClusterLabel(
      _collectLabelClusters(element, maxDepth: maxDepth, includeRoot: true),
    );
    if (_isMeaningfulText(clusteredLabel)) {
      return clusteredLabel;
    }

    final texts = <String>[];

    void visit(Element current, int depth, {required bool isRoot}) {
      if (depth > maxDepth || texts.length >= 6) {
        return;
      }

      if (!isRoot && (_isIgnoredWidget(current.widget) || _isHiddenElement(current))) {
        return;
      }

      if (!isRoot && _isNestedInteractiveBoundary(current)) {
        return;
      }

      final text = _extractTextFromWidget(current.widget);
      if (_isMeaningfulText(text)) {
        texts.add(text);
      }

      current.visitChildElements((child) => visit(child, depth + 1, isRoot: false));
    }

    visit(element, 0, isRoot: true);
    return _composeLabel(texts);
  }

  List<_LabelCluster> _collectLabelClusters(
    Element element, {
    required int maxDepth,
    required bool includeRoot,
  }) {
    if (_isIgnoredWidget(element.widget) || _isHiddenElement(element)) {
      return const <_LabelCluster>[];
    }

    final clusters = <_LabelCluster>[];
    final dedupe = <String>{};

    void visit(Element current, int depth, {required bool isRoot}) {
      if (depth > maxDepth) {
        return;
      }

      if (!isRoot && (_isIgnoredWidget(current.widget) || _isHiddenElement(current))) {
        return;
      }

      if (!isRoot && _isNestedInteractiveBoundary(current)) {
        return;
      }

      if (includeRoot || !isRoot) {
        final localCluster = _collectLocalCluster(current);
        if (_isMeaningfulText(localCluster.label)) {
          final key = '${localCluster.label}|${localCluster.textCount}';
          if (dedupe.add(key)) {
            clusters.add(_LabelCluster(
              label: localCluster.label,
              textCount: localCluster.textCount,
              depth: depth,
            ));
          }
        }
      }

      current.visitChildElements((child) => visit(child, depth + 1, isRoot: false));
    }

    visit(element, 0, isRoot: true);
    return clusters;
  }

  _LabelCluster _collectLocalCluster(Element element, {int maxDepth = 8}) {
    if (_isIgnoredWidget(element.widget) || _isHiddenElement(element)) {
      return const _LabelCluster(label: '', textCount: 0, depth: 0);
    }

    final texts = <String>[];

    void visit(Element current, int depth, {required bool isRoot}) {
      if (depth > maxDepth || texts.length >= 3) {
        return;
      }

      if (!isRoot && (_isIgnoredWidget(current.widget) || _isHiddenElement(current))) {
        return;
      }

      if (!isRoot && _isNestedInteractiveBoundary(current)) {
        return;
      }

      final text = _extractTextFromWidget(current.widget);
      if (_isMeaningfulText(text) && !texts.contains(text)) {
        texts.add(text);
      }

      current.visitChildElements((child) => visit(child, depth + 1, isRoot: false));
    }

    visit(element, 0, isRoot: true);
    return _LabelCluster(
      label: _composeLabel(texts),
      textCount: texts.length,
      depth: 0,
    );
  }

  String _bestClusterLabel(List<_LabelCluster> clusters) {
    final meaningful = clusters.where((cluster) => _isMeaningfulText(cluster.label)).toList();
    if (meaningful.isEmpty) {
      return '';
    }

    meaningful.sort((a, b) {
      final aHasLetters = RegExp(r'[A-Za-z]').hasMatch(a.label);
      final bHasLetters = RegExp(r'[A-Za-z]').hasMatch(b.label);
      if (aHasLetters != bHasLetters) {
        return aHasLetters ? -1 : 1;
      }
      final countCompare = a.textCount.compareTo(b.textCount);
      if (countCompare != 0) {
        return countCompare;
      }
      final depthCompare = a.depth.compareTo(b.depth);
      if (depthCompare != 0) {
        return depthCompare;
      }
      return a.label.length.compareTo(b.label.length);
    });

    return meaningful.first.label;
  }

  String _extractTextFromWidget(Widget? widget) {
    if (widget == null) return '';

    if (widget is Text) {
      if (widget.data != null) return _normalizeText(widget.data!);
      if (widget.textSpan != null) {
        return _normalizeText(widget.textSpan!.toPlainText());
      }
    }

    if (widget is RichText) {
      return _normalizeText(widget.text.toPlainText());
    }

    if (widget is IconButton) {
      return _firstNonEmpty([
        widget.tooltip,
        _describeIconData(_iconDataFromWidget(widget.icon)),
      ]);
    }

    if (widget is ButtonStyleButton) {
      return _extractTextFromWidget(widget.child);
    }

    if (widget is ListTile) {
      return _composeLabel([
        _extractTextFromWidget(widget.title),
        _extractTextFromWidget(widget.subtitle),
      ]);
    }

    if (widget is SwitchListTile) {
      return _composeLabel([
        _extractTextFromWidget(widget.title),
        _extractTextFromWidget(widget.subtitle),
      ]);
    }

    if (widget is CheckboxListTile) {
      return _composeLabel([
        _extractTextFromWidget(widget.title),
        _extractTextFromWidget(widget.subtitle),
      ]);
    }

    if (widget is RadioListTile) {
      final dynamic dynamicWidget = widget;
      return _composeLabel([
        _extractTextFromWidget(dynamicWidget.title as Widget?),
        _extractTextFromWidget(dynamicWidget.subtitle as Widget?),
      ]);
    }

    if (widget is FilterChip) {
      return _extractTextFromWidget(widget.label);
    }

    if (widget is ChoiceChip) {
      return _extractTextFromWidget(widget.label);
    }

    if (widget is ActionChip) {
      return _extractTextFromWidget(widget.label);
    }

    if (widget is InputChip) {
      return _extractTextFromWidget(widget.label);
    }

    if (widget is TextField) {
      return _composeLabel([
        widget.decoration?.labelText,
        widget.decoration?.hintText,
        widget.controller?.text,
      ]);
    }

    if (widget is TextFormField) {
      final decoration = _readInputDecoration(widget);
      return _composeLabel([
        decoration?.labelText,
        decoration?.hintText,
        _readTextFormFieldValue(widget),
      ]);
    }

    if (widget is Radio) {
      final dynamic dynamicWidget = widget;
      return _composeLabel([
        dynamicWidget.value?.toString(),
      ], fallback: 'Radio');
    }

    if (widget is Tooltip) {
      return _firstNonEmpty([
        widget.message,
        widget.richMessage?.toPlainText(),
      ]);
    }

    if (widget is NavigationDestination) {
      return _normalizeText(widget.label);
    }

    if (widget is Tab) {
      return _composeLabel([
        widget.text,
        _describeIconData(_iconDataFromWidget(widget.icon)),
      ]);
    }

    if (widget is Icon) {
      return _describeIconData(widget.icon);
    }

    return '';
  }

  bool _isNestedInteractiveBoundary(Element element) {
    return _detectInteractiveCandidate(element) != null ||
        element.widget is BottomNavigationBar ||
        element.widget is NavigationBar ||
        element.widget is TabBar;
  }

  bool _shouldPruneInteractiveSubtree(Widget widget) {
    if (widget is GestureDetector || widget is InkWell) {
      return false;
    }

    return widget is ButtonStyleButton ||
        widget is BottomNavigationBar ||
        widget is NavigationBar ||
        widget is TabBar ||
        widget is IconButton ||
        widget is FloatingActionButton ||
        widget is ListTile ||
        widget is SwitchListTile ||
        widget is CheckboxListTile ||
        widget is Radio ||
        widget is RadioListTile ||
        widget is FilterChip ||
        widget is ChoiceChip ||
        widget is ActionChip ||
        widget is InputChip ||
        widget is Switch ||
        widget is Checkbox ||
        widget is Slider ||
        widget is DropdownButton ||
        widget is DropdownButtonFormField;
  }

  bool _isIgnoredWidget(Widget widget) {
    const ignoredTypes = <String>[
      'AIAgent',
      'AgentChatBar',
      'AIApprovalDialog',
      'AIConsentDialog',
      'AIConsentInlineCard',
      'AgentOverlay',
      '_ThinkingPill',
      '_AIBadge',
      '_LoadingDots',
      'FloatingOverlayWrapper',
      'FloatingOverlayControllerWidget',
    ];

    final widgetType = widget.runtimeType.toString();
    for (final ignored in ignoredTypes) {
      if (widgetType.contains(ignored)) {
        return true;
      }
    }
    return false;
  }

  bool _isHiddenSubtree(Widget widget) {
    if (widget is Offstage) {
      return widget.offstage;
    }
    if (widget is Visibility) {
      return !widget.visible;
    }
    if (widget is TickerMode) {
      return !widget.enabled;
    }
    if (_isInactiveModalRouteStatus(widget)) {
      return true;
    }
    return false;
  }

  bool _isHiddenElement(Element element) {
    if (_isHiddenSubtree(element.widget)) {
      return true;
    }
    if (_isInactiveIndexedStackBranch(element)) {
      return true;
    }
    return false;
  }

  bool _isInactiveModalRouteStatus(Widget widget) {
    final widgetType = widget.runtimeType.toString();
    if (!widgetType.contains('_ModalScopeStatus')) {
      return false;
    }

    try {
      final dynamic dynamicWidget = widget;
      final isCurrent = dynamicWidget.isCurrent;
      if (isCurrent is bool) {
        return !isCurrent;
      }
    } catch (_) {}
    return false;
  }

  bool _isTraceWidget(Widget widget) {
    return widget is MaterialApp ||
        widget is Navigator ||
        widget is Scaffold ||
        widget is BottomNavigationBar ||
        widget is NavigationBar ||
        widget is TabBar ||
        widget is ListTile ||
        widget is SwitchListTile ||
        widget is CheckboxListTile ||
        widget is IconButton ||
        widget is ButtonStyleButton ||
        widget is GestureDetector ||
        widget is InkWell ||
        widget is ScrollView ||
        widget is TextField ||
        widget is TextFormField ||
        widget.runtimeType.toString().contains('ProfileScreen');
  }

  String _describeElementPath(Element element, {int maxAncestors = 14}) {
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

  String _describeChildWidgets(Element element, {int limit = 20}) {
    final children = <String>[];
    element.visitChildElements((child) {
      if (children.length >= limit) {
        return;
      }
      children.add(child.widget.runtimeType.toString());
    });
    if (children.isEmpty) {
      return '(none)';
    }
    return children.join(', ');
  }

  String _summarizeElements(List<InteractiveElement> elements, {int limit = 8}) {
    if (elements.isEmpty) {
      return '(none)';
    }
    return elements
        .take(limit)
        .map((element) => '[${element.index}] ${element.label} (${element.type.name})')
        .join(' | ');
  }

  bool _shouldPruneIgnoredSubtree(Widget widget) {
    const pruneTypes = <String>[
      'AgentChatBar',
      'AIApprovalDialog',
      'AIConsentDialog',
      'AIConsentInlineCard',
      'AgentOverlay',
      '_ThinkingPill',
      '_AIBadge',
      '_LoadingDots',
      'FloatingOverlayWrapper',
      'FloatingOverlayControllerWidget',
    ];

    final widgetType = widget.runtimeType.toString();
    for (final pruneType in pruneTypes) {
      if (widgetType.contains(pruneType)) {
        return true;
      }
    }
    return false;
  }

  String _navigationDestinationLabel(Widget destination) {
    if (destination is NavigationDestination) {
      return _composeLabel([
        destination.label,
        _describeIconData(_iconDataFromWidget(destination.icon)),
      ], fallback: 'Destination');
    }
    return _composeLabel([
      _extractTextFromWidget(destination),
    ], fallback: 'Destination');
  }

  String _tabLabel(Widget tab) {
    if (tab is Tab) {
      return _composeLabel([
        tab.text,
        _describeIconData(_iconDataFromWidget(tab.icon)),
      ], fallback: 'Tab');
    }
    return _composeLabel([
      _extractTextFromWidget(tab),
    ], fallback: 'Tab');
  }

  IconData? _iconDataFromWidget(Widget? widget) {
    if (widget is Icon) {
      return widget.icon;
    }
    return null;
  }

  String _describeIconData(IconData? icon) {
    if (icon == null) return '';
    if (icon == Icons.arrow_back || icon == Icons.arrow_back_ios || icon == Icons.arrow_back_ios_new) return 'Back';
    if (icon == Icons.clear || icon == Icons.close || icon == Icons.cancel) return 'Clear';
    if (icon == Icons.filter_alt || icon == Icons.filter_list) return 'Filter';
    if (icon == Icons.sort || icon == Icons.swap_vert) return 'Sort';
    if (icon == Icons.home || icon == Icons.home_outlined || icon == Icons.home_filled) return 'Home';
    if (icon == Icons.search || icon == Icons.search_outlined) return 'Search';
    if (icon == Icons.shopping_cart || icon == Icons.shopping_cart_outlined) return 'Cart';
    if (icon == Icons.person || icon == Icons.person_outline || icon == Icons.account_circle) return 'Profile';
    if (icon == Icons.settings || icon == Icons.settings_outlined) return 'Settings';
    if (icon == Icons.notifications || icon == Icons.notifications_outlined) return 'Notifications';
    if (icon == Icons.calendar_today || icon == Icons.calendar_month || icon == Icons.date_range) return 'Calendar';
    if (icon == Icons.logout || icon == Icons.exit_to_app) return 'Log Out';
    final name = icon.toString().toLowerCase();
    if (name.contains('arrow_back') || name.contains('back')) return 'Back';
    if (name.contains('clear') || name.contains('close') || name.contains('cancel')) return 'Clear';
    if (name.contains('filter')) return 'Filter';
    if (name.contains('sort')) return 'Sort';
    if (name.contains('home')) return 'Home';
    if (name.contains('search')) return 'Search';
    if (name.contains('shopping_cart') || name.contains('cart')) return 'Cart';
    if (name.contains('person') || name.contains('profile')) return 'Profile';
    if (name.contains('settings')) return 'Settings';
    if (name.contains('notifications')) return 'Notifications';
    if (name.contains('calendar')) return 'Calendar';
    if (name.contains('logout')) return 'Log Out';
    return '';
  }

  String _composeLabel(List<String?> parts, {String fallback = ''}) {
    final filtered = <String>[];
    for (final part in parts) {
      final normalized = _normalizeText(part ?? '');
      if (_isMeaningfulText(normalized) && !filtered.contains(normalized)) {
        filtered.add(normalized);
      }
    }
    if (filtered.isEmpty) {
      return _normalizeText(fallback);
    }
    if (filtered.length == 1) {
      return filtered.first;
    }
    return '${filtered.first} - ${filtered[1]}';
  }

  String _firstNonEmpty(List<String?> parts) {
    for (final part in parts) {
      final normalized = _normalizeText(part ?? '');
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  String _normalizeText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _isMeaningfulText(String value) {
    final normalized = _normalizeText(value);
    if (normalized.isEmpty) return false;
    const trivialGlyphs = <String>{'•', '·', '|', '-', '—', '_', '/', '\\'};
    if (trivialGlyphs.contains(normalized)) return false;
    if (normalized.runes.length == 1) {
      final rune = normalized.runes.first;
      if (rune >= 0xE000 && rune <= 0xF8FF) {
        return false;
      }
    }
    return true;
  }

  InputDecoration? _readInputDecoration(dynamic widget) {
    try {
      final dynamic dynamicWidget = widget;
      return dynamicWidget.decoration as InputDecoration?;
    } catch (_) {
      return null;
    }
  }

  String? _readTextFormFieldValue(dynamic widget) {
    try {
      final dynamic dynamicWidget = widget;
      final controllerText = dynamicWidget.controller?.text as String?;
      if (controllerText != null && controllerText.trim().isNotEmpty) {
        return controllerText.trim();
      }
      final initialValue = dynamicWidget.initialValue;
      if (initialValue is String && initialValue.trim().isNotEmpty) {
        return initialValue.trim();
      }
    } catch (_) {}
    return null;
  }

  bool _readInputEnabled(dynamic widget) {
    try {
      final dynamic dynamicWidget = widget;
      final enabled = dynamicWidget.enabled;
      if (enabled is bool) {
        return enabled;
      }
    } catch (_) {}
    return true;
  }

  Map<String, dynamic> _canonicalizeProperties(
    Element element,
    ElementType type,
    Map<String, dynamic> properties,
  ) {
    final canonical = Map<String, dynamic>.from(properties);
    final elementId = _elementId(element);
    canonical['id'] = elementId;
    canonical['widgetType'] = element.widget.runtimeType.toString();
    canonical.putIfAbsent('role', () => _defaultRoleForType(type));

    final parentId = _nearestStructuredAncestorId(element);
    if (parentId != null) {
      canonical['parentId'] = parentId;
    }

    final key = _serializableKey(element.widget.key);
    if (key != null) {
      canonical['key'] = key;
    }

    final tooltip = _resolveTooltipForElement(element);
    if (tooltip.isNotEmpty) {
      canonical['tooltip'] = tooltip;
    }

    final scrollHostId = _nearestScrollHostId(
      element,
      includeSelf: type == ElementType.scrollable,
    );
    if (scrollHostId != null) {
      canonical['scrollHostId'] = scrollHostId;
    }

    if (type == ElementType.scrollable) {
      canonical['scrollHostId'] = elementId;
      canonical.putIfAbsent(
        'orientation',
        () => _describeScrollOrientation(element.widget),
      );
      final bounds = _encodeBounds(element);
      if (bounds != null) {
        canonical['bounds'] = bounds;
      }
    }

    canonical.removeWhere(
      (key, value) => value == null || (value is String && value.trim().isEmpty),
    );
    return canonical;
  }

  String _defaultRoleForType(ElementType type) {
    switch (type) {
      case ElementType.pressable:
        return 'button';
      case ElementType.textInput:
        return 'textbox';
      case ElementType.switchToggle:
        return 'switch';
      case ElementType.scrollable:
        return 'scrollable';
      case ElementType.slider:
        return 'slider';
      case ElementType.picker:
        return 'combobox';
      case ElementType.datePicker:
        return 'date-picker';
      case ElementType.checkbox:
        return 'checkbox';
      case ElementType.text:
        return 'text';
    }
  }

  String _elementId(Element element) => 'el-${identityHashCode(element)}';

  String? _nearestStructuredAncestorId(Element element) {
    String? parentId;
    var depth = 0;
    element.visitAncestorElements((ancestor) {
      depth += 1;
      if (depth > 12) {
        return false;
      }
      if (_isIgnoredWidget(ancestor.widget) || _isHiddenElement(ancestor)) {
        return true;
      }
      if (_isCompositeWidget(ancestor.widget) ||
          _detectInteractiveCandidate(ancestor) != null ||
          _isCanonicalScrollHost(ancestor)) {
        parentId = _elementId(ancestor);
        return false;
      }
      return true;
    });
    return parentId;
  }

  String? _nearestScrollHostId(Element element, {required bool includeSelf}) {
    if (includeSelf && _isCanonicalScrollHost(element)) {
      return _elementId(element);
    }

    String? scrollHostId;
    element.visitAncestorElements((ancestor) {
      if (_isCanonicalScrollHost(ancestor)) {
        scrollHostId = _elementId(ancestor);
        return false;
      }
      return true;
    });
    return scrollHostId;
  }

  bool _isCompositeWidget(Widget widget) {
    return widget is BottomNavigationBar ||
        widget is NavigationBar ||
        widget is TabBar;
  }

  bool _isCanonicalScrollHost(Element element) {
    final widget = element.widget;
    if (widget is ScrollView || widget is PageView) {
      if (_isInsideTextInput(element)) {
        return false;
      }
      return true;
    }
    if (widget is! Scrollable) {
      return false;
    }

    if (_isInsideTextInput(element)) {
      return false;
    }

    var hasScrollAncestor = false;
    element.visitAncestorElements((ancestor) {
      final ancestorWidget = ancestor.widget;
      if (ancestorWidget is ScrollView ||
          ancestorWidget is PageView ||
          ancestorWidget is Scrollable) {
        hasScrollAncestor = true;
        return false;
      }
      return true;
    });
    return !hasScrollAncestor;
  }

  bool _isInsideTextInput(Element element) {
    if (_isTextInputWidget(element.widget)) {
      return true;
    }

    var insideTextInput = false;
    element.visitAncestorElements((ancestor) {
      if (_isTextInputWidget(ancestor.widget)) {
        insideTextInput = true;
        return false;
      }
      return true;
    });
    return insideTextInput;
  }

  bool _isTextInputWidget(Widget widget) {
    return widget is TextField ||
        widget is TextFormField ||
        widget.runtimeType.toString().contains('EditableText') ||
        widget.runtimeType.toString().contains('CupertinoTextField');
  }

  bool _isInactiveIndexedStackBranch(Element element) {
    var inactive = false;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is! IndexedStack) {
        return true;
      }
      final activeIndex = widget.index ?? 0;
      var branchIndex = 0;
      var matched = false;
      ancestor.visitChildElements((child) {
        if (matched) {
          return;
        }
        if (_subtreeContains(child, element)) {
          matched = true;
          return;
        }
        branchIndex += 1;
      });
      if (matched && branchIndex != activeIndex) {
        inactive = true;
        return false;
      }
      return true;
    });
    return inactive;
  }

  String? _serializableKey(Key? key) {
    if (key is ValueKey<Object?>) {
      final value = key.value;
      if (value is String || value is num || value is bool) {
        return value.toString();
      }
      if (value is Enum) {
        return value.name;
      }
    }
    return null;
  }

  String _resolveTooltipForElement(Element element) {
    final localTooltip = _extractTooltipFromWidget(element.widget);
    if (localTooltip.isNotEmpty) {
      return localTooltip;
    }

    String tooltip = '';
    var depth = 0;
    element.visitAncestorElements((ancestor) {
      depth += 1;
      if (depth > 10) {
        return false;
      }
      final candidate = _extractTooltipFromWidget(ancestor.widget);
      if (candidate.isNotEmpty) {
        tooltip = candidate;
        return false;
      }
      return true;
    });
    return tooltip;
  }

  String _extractTooltipFromWidget(Widget? widget) {
    if (widget == null) {
      return '';
    }
    if (widget is Tooltip) {
      return _firstNonEmpty([
        widget.message,
        widget.richMessage?.toPlainText(),
      ]);
    }
    if (widget is IconButton) {
      return _normalizeText(widget.tooltip ?? '');
    }
    if (widget is FloatingActionButton) {
      return _normalizeText(widget.tooltip ?? '');
    }

    final widgetType = widget.runtimeType.toString();
    if (!widgetType.contains('Tooltip')) {
      return '';
    }

    try {
      final dynamic dynamicWidget = widget;
      final String? message = dynamicWidget.message as String?;
      if (message != null && message.trim().isNotEmpty) {
        return _normalizeText(message);
      }
      final InlineSpan? richMessage = dynamicWidget.richMessage as InlineSpan?;
      if (richMessage != null) {
        return _normalizeText(richMessage.toPlainText());
      }
    } catch (_) {}
    return '';
  }

  bool _hasEquivalentInteractiveAncestorLabel(Element element, String label) {
    final normalizedLabel = _normalizeText(label);
    if (normalizedLabel.isEmpty) {
      return false;
    }

    var foundDuplicate = false;
    var depth = 0;
    element.visitAncestorElements((ancestor) {
      depth += 1;
      if (depth > 8) {
        return false;
      }
      if (_isIgnoredWidget(ancestor.widget) || _isHiddenElement(ancestor)) {
        return true;
      }
      final candidate = _detectInteractiveCandidate(ancestor);
      if (candidate == null) {
        return true;
      }
      final ancestorLabel = _normalizeText(_resolveCandidateLabel(ancestor, candidate));
      if (ancestorLabel == normalizedLabel) {
        foundDuplicate = true;
        return false;
      }
      return true;
    });
    return foundDuplicate;
  }

  String? _encodeBounds(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox) {
      return null;
    }
    try {
      final position = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      return '${position.dx.toStringAsFixed(1)},'
          '${position.dy.toStringAsFixed(1)},'
          '${size.width.toStringAsFixed(1)},'
          '${size.height.toStringAsFixed(1)}';
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _stateProperties({
    String? role,
    Object? value,
    bool? checked,
    bool? selected,
    bool? enabled,
    bool? disabled,
    String? hint,
    String? placeholder,
    String? orientation,
  }) {
    final properties = <String, dynamic>{};
    if (role != null && role.isNotEmpty) {
      properties['role'] = role;
    }
    if (value != null) {
      properties['value'] = value;
    }
    if (checked != null) {
      properties['checked'] = checked;
    }
    if (selected != null) {
      properties['selected'] = selected;
    }
    if (enabled != null) {
      properties['enabled'] = enabled;
    }
    if (disabled != null) {
      properties['disabled'] = disabled;
    }
    if (hint != null && hint.trim().isNotEmpty) {
      properties['hint'] = hint.trim();
    }
    if (placeholder != null && placeholder.trim().isNotEmpty) {
      properties['placeholder'] = placeholder.trim();
    }
    if (orientation != null && orientation.trim().isNotEmpty) {
      properties['orientation'] = orientation.trim();
    }
    return properties;
  }

  String _describeScrollOrientation(Widget widget) {
    if (widget is ScrollView) {
      return widget.scrollDirection == Axis.horizontal ? 'horizontal' : 'vertical';
    }
    if (widget is PageView) {
      return widget.scrollDirection == Axis.horizontal ? 'horizontal' : 'vertical';
    }
    if (widget is Scrollable) {
      final axisDirection = widget.axisDirection;
      if (axisDirection == AxisDirection.left || axisDirection == AxisDirection.right) {
        return 'horizontal';
      }
      return 'vertical';
    }
    return '';
  }

  String _scrollableFallbackLabel(String orientation) {
    switch (orientation) {
      case 'horizontal':
        return 'Horizontal scroll area';
      case 'vertical':
        return 'Vertical scroll area';
      default:
        return 'Scrollable content';
    }
  }

  List<InteractiveElement> _walkSemanticsTree() {
    final results = <InteractiveElement>[];
    final owner = RendererBinding.instance.rootPipelineOwner.semanticsOwner;
    final root = owner?.rootSemanticsNode;
    if (root == null) {
      return results;
    }

    final counter = _Counter(1);

    void visit(SemanticsNode node, int depth) {
      if (depth > _maxSemanticsDepth) return;

      final data = node.getSemanticsData();
      final flags = data.flagsCollection;
      final label = _normalizeText(_firstNonEmpty([
        data.label,
        data.value,
        data.hint,
        data.tooltip,
      ]));
      final isTappable = data.hasAction(SemanticsAction.tap);
      final isScrollable = data.hasAction(SemanticsAction.scrollDown) ||
          data.hasAction(SemanticsAction.scrollUp) ||
          data.hasAction(SemanticsAction.scrollLeft) ||
          data.hasAction(SemanticsAction.scrollRight);
      final isTextField = flags.isTextField;
      final isSlider = flags.isSlider;
      final isCheckable = flags.isChecked != ui.CheckedState.none;
      final isHidden = flags.isHidden;
      final isSelected = _tristateToBool(flags.isSelected);
      final isEnabled = _tristateToBool(flags.isEnabled);
      final isToggled = _tristateToBool(flags.isToggled);
      final isReadOnly = flags.isReadOnly;

      if (!isHidden && (label.isNotEmpty || isTappable || isScrollable || isTextField || isSlider)) {
        final type = isTextField
            ? ElementType.textInput
            : isSlider
                ? ElementType.slider
                : isCheckable
                    ? ElementType.switchToggle
                    : isScrollable
                        ? ElementType.scrollable
                        : isTappable
                            ? ElementType.pressable
                            : ElementType.text;
        final semanticsProperties = <String, dynamic>{
          'id': 'semantics-${node.id}',
          'widgetType': 'SemanticsNode',
          'role': _defaultRoleForType(type),
          if (data.value.isNotEmpty) 'value': data.value,
          if (data.hint.isNotEmpty) 'hint': data.hint,
          if (data.tooltip.isNotEmpty) 'tooltip': data.tooltip,
          if (isCheckable) 'checked': flags.isChecked == ui.CheckedState.isTrue,
          if (isTextField) 'readOnly': isReadOnly,
          if (isScrollable) 'orientation': _semanticsOrientation(data),
        };
        if (isToggled != null) {
          semanticsProperties['checked'] = isToggled;
        }
        if (isSelected != null) {
          semanticsProperties['selected'] = isSelected;
        }
        if (isEnabled != null) {
          semanticsProperties['enabled'] = isEnabled;
        }

        results.add(
          InteractiveElement(
            index: counter.value,
            label: label.isNotEmpty ? label : _fallbackLabel(type),
            type: type,
            semanticsNodeId: node.id,
            properties: semanticsProperties,
          ),
        );
        counter.value += 1;
      }

      node.visitChildren((child) {
        visit(child, depth + 1);
        return true;
      });
    }

    visit(root, 0);
    return results;
  }

  bool? _tristateToBool(Object value) {
    try {
      final dynamic dynamicValue = value;
      return dynamicValue.toBoolOrNull() as bool?;
    } catch (_) {
      return null;
    }
  }

  String _semanticsOrientation(SemanticsData data) {
    final hasHorizontal =
        data.hasAction(SemanticsAction.scrollLeft) ||
        data.hasAction(SemanticsAction.scrollRight);
    final hasVertical =
        data.hasAction(SemanticsAction.scrollUp) ||
        data.hasAction(SemanticsAction.scrollDown);
    if (hasVertical && !hasHorizontal) {
      return 'vertical';
    }
    if (hasHorizontal && !hasVertical) {
      return 'horizontal';
    }
    return '';
  }

  String _fallbackLabel(ElementType type) {
    switch (type) {
      case ElementType.pressable:
        return 'Interactive Element';
      case ElementType.textInput:
        return 'Text Field';
      case ElementType.switchToggle:
        return 'Switch';
      case ElementType.scrollable:
        return 'Scrollable content';
      case ElementType.slider:
        return 'Slider';
      case ElementType.picker:
        return 'Picker';
      case ElementType.datePicker:
        return 'Date Picker';
      case ElementType.checkbox:
        return 'Checkbox';
      case ElementType.text:
        return 'Text';
    }
  }

  WireframeSnapshot? captureWireframe({String? screenName, int maxElements = 50}) {
    final elements = walk(null);
    if (elements.isEmpty) return null;

    final capped = elements.take(maxElements).toList();
    final components = <WireframeComponent>[];

    for (final element in capped) {
      final bounds = _getElementBounds(element);
      if (bounds == null) continue;

      components.add(WireframeComponent(
        label: element.label,
        elementType: element.type.name,
        x: (bounds.left * 1000).round(),
        y: (bounds.top * 1000).round(),
        width: (bounds.width * 1000).round(),
        height: (bounds.height * 1000).round(),
      ));
    }

    if (components.isEmpty) return null;

    final window = WidgetsBinding.instance.platformDispatcher.views.first;
    final deviceWidth = window.physicalSize.width / window.devicePixelRatio;
    final deviceHeight = window.physicalSize.height / window.devicePixelRatio;

    return WireframeSnapshot(
      screen: screenName ?? 'Unknown',
      components: components,
      deviceWidth: deviceWidth.round(),
      deviceHeight: deviceHeight.round(),
      capturedAt: DateTime.now().toIso8601String(),
    );
  }

  Rect? _getElementBounds(InteractiveElement element) {
    final renderObject = element.element?.renderObject;
    if (renderObject is RenderBox) {
      try {
        final position = renderObject.localToGlobal(Offset.zero);
        final size = renderObject.size;
        return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class _InteractiveCandidate {
  final ElementType type;
  final List<String?> explicitLabels;
  final String iconFallback;
  final String genericFallback;
  final Map<String, dynamic> properties;
  final bool allowDeepLabel;

  const _InteractiveCandidate({
    required this.type,
    this.explicitLabels = const <String?>[],
    this.iconFallback = '',
    this.genericFallback = '',
    this.properties = const <String, dynamic>{},
    this.allowDeepLabel = true,
  });
}

class _LabelCluster {
  final String label;
  final int textCount;
  final int depth;

  const _LabelCluster({
    required this.label,
    required this.textCount,
    required this.depth,
  });
}

class _Counter {
  int value;
  _Counter(this.value);
}
