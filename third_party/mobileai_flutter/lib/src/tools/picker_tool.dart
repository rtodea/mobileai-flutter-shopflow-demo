import 'package:flutter/material.dart';

import '../core/types.dart';
import '../utils/logger.dart';
import 'types.dart';

/// PickerTool — Select values from dropdown/picker components.
///
/// Handles multiple picker types:
/// - DropdownButton (Material Design dropdowns)
/// - PopupMenuButton (popup menus)
/// - ListTile-based selections
/// - Generic onTap handlers with value matching
class PickerTool implements AgentTool {
  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'select_picker',
    description:
        'Select a value from a picker/dropdown by its index. Provide the exact value string to select.',
    effect: ToolEffect.select,
    parameters: {
      'index': ToolParam(
        type: 'integer',
        description: 'The index of the picker element',
      ),
      'value': ToolParam(
        type: 'string',
        description: 'The value to select (must match an available option)',
      ),
    },
    handler: (args) => throw UnimplementedError('Handled by execute()'),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    // Validate parameters
    final index = args['index'] as int?;
    final value = args['value'] as String?;

    if (index == null || value == null) {
      throw Exception('Missing required parameters: index, value');
    }

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      throw Exception('Value cannot be empty');
    }

    final target = await context.resolveInteractiveElement(
      index,
      actionName: 'select_picker',
    );

    // Verify it's a picker (or treat generic pressables as potential pickers)
    if (target.type != ElementType.picker &&
        target.type != ElementType.pressable) {
      throw Exception(
        'Element [$index] ${target.label} is not a picker (type: ${target.type}).',
      );
    }

    // Check widget availability
    if (target.element == null || !target.element!.mounted) {
      throw Exception(
        'Cannot select from picker [$index]: no widget reference available.',
      );
    }

    // Try to select the value
    final success = await _performPickerSelection(
      target.element!,
      trimmedValue,
    );
    if (!success) {
      throw Exception('Failed to select "$trimmedValue" from picker [$index].');
    }

    return 'Selected "$trimmedValue" from picker [$index] ${target.label}.';
  }

  Future<bool> _performPickerSelection(Element element, String value) async {
    // Strategy 1: DropdownButton - find and select matching value
    DropdownButton? dropdown;
    void findDropdown(Element e) {
      if (dropdown != null) return;
      if (e.widget is DropdownButton) {
        dropdown = e.widget as DropdownButton;
        return;
      }
      e.visitChildElements(findDropdown);
    }

    findDropdown(element);

    if (dropdown != null) {
      Logger.info(
        '[PickerTool] Found DropdownButton, looking for value: $value',
      );
      // Find matching item in items list
      final items = dropdown!.items;
      if (items != null) {
        for (final item in items) {
          if (item.value != null &&
              (item.value.toString() == value ||
                  item.value.toString().toLowerCase() == value.toLowerCase())) {
            dropdown!.onChanged?.call(item.value);
            Logger.info(
              '[PickerTool] Selected value from DropdownButton: ${item.value}',
            );
            return true;
          }
          // Check if label matches
          final customChild = item.child;
          if (customChild is Text) {
            final childText = customChild.data ?? '';
            if (childText.toLowerCase() == value.toLowerCase()) {
              dropdown!.onChanged?.call(item.value);
              Logger.info(
                '[PickerTool] Selected from DropdownButton by label: $value',
              );
              return true;
            }
          }
        }
        Logger.warn('[PickerTool] No matching value found in DropdownButton');
      }
    }

    // Strategy 2: PopupMenuButton - try direct selection
    PopupMenuButton? popupMenu;
    void findPopupMenu(Element e) {
      if (popupMenu != null) return;
      if (e.widget is PopupMenuButton) {
        popupMenu = e.widget as PopupMenuButton;
        return;
      }
      e.visitChildElements(findPopupMenu);
    }

    findPopupMenu(element);

    if (popupMenu != null) {
      Logger.info(
        '[PickerTool] Found PopupMenuButton, attempting direct selection: $value',
      );
      try {
        // Try to call onSelected directly with the value
        popupMenu!.onSelected?.call(value);
        Logger.info('[PickerTool] Selected value from PopupMenuButton: $value');
        return true;
      } catch (e) {
        Logger.warn('[PickerTool] Failed to select from PopupMenuButton: $e');
      }
    }

    // Strategy 3: ListTile within a dropdown-like container
    List<ListTile> listTiles = [];
    void collectListTiles(Element e) {
      if (e.widget is ListTile) {
        listTiles.add(e.widget as ListTile);
      }
      e.visitChildElements(collectListTiles);
    }

    collectListTiles(element);

    if (listTiles.isNotEmpty) {
      Logger.info(
        '[PickerTool] Found ${listTiles.length} ListTiles, looking for match: $value',
      );
      for (final tile in listTiles) {
        final title = tile.title;
        String tileText = '';
        if (title is Text) {
          tileText = title.data ?? '';
        } else if (title is Row) {
          for (final child in title.children) {
            if (child is Text) {
              tileText = child.data ?? '';
              break;
            }
          }
        }

        if (tileText.toLowerCase() == value.toLowerCase() ||
            tileText.toLowerCase().contains(value.toLowerCase())) {
          tile.onTap?.call();
          Logger.info(
            '[PickerTool] Selected ListTile by text match: $tileText',
          );
          return true;
        }
      }
      Logger.warn('[PickerTool] No matching ListTile found');
    }

    // Strategy 4: Search for GestureDetector/InkWell with matching text
    final foundMatch = _searchForHandlerWithText(element, value);
    if (foundMatch) {
      return true;
    }

    Logger.warn('[PickerTool] No strategy succeeded for picker selection');
    return false;
  }

  // Helper to search for gesture handlers with matching text
  bool _searchForHandlerWithText(Element element, String searchValue) {
    bool foundHandler = false;

    bool searchElement(Element e) {
      if (foundHandler) return true;

      final widget = e.widget;

      // Check for GestureDetector with onTap
      if (widget is GestureDetector && widget.onTap != null) {
        // Check if this detector contains matching text
        final hasMatch = _containsMatchingText(e, searchValue);
        if (hasMatch) {
          widget.onTap!();
          foundHandler = true;
          Logger.info(
            '[PickerTool] Invoked onTap on GestureDetector with matching text',
          );
          return true;
        }
      }

      // Check for InkWell with onTap
      if (widget is InkWell && widget.onTap != null) {
        final hasMatch = _containsMatchingText(e, searchValue);
        if (hasMatch) {
          widget.onTap!();
          foundHandler = true;
          Logger.info(
            '[PickerTool] Invoked onTap on InkWell with matching text',
          );
          return true;
        }
      }

      // Search children
      e.visitChildElements(searchElement);
      return foundHandler;
    }

    searchElement(element);
    return foundHandler;
  }

  // Helper to check if element contains matching text
  bool _containsMatchingText(Element element, String searchValue) {
    bool hasMatch = false;

    void checkText(Element e) {
      if (hasMatch) return;
      if (e.widget is Text) {
        final text = (e.widget as Text).data ?? '';
        if (text.toLowerCase().contains(searchValue.toLowerCase())) {
          hasMatch = true;
        }
      }
      e.visitChildElements(checkText);
    }

    element.visitChildElements(checkText);
    return hasMatch;
  }
}
