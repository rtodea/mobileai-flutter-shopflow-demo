import 'package:flutter/material.dart';

import '../core/types.dart';
import '../utils/logger.dart';
import 'types.dart';

/// DatePickerTool — Set date picker values using ISO 8601 format dates.
///
/// Handles multiple date picker implementations:
/// - TextField/TextFormField with date input
/// - InkWell/GestureDetector with onTap triggering showDatePicker
/// - Direct state manipulation where possible
/// - ISO 8601 date format support (YYYY-MM-DD or YYYY-MM-DDTHH:mm:ss)
class DatePickerTool implements AgentTool {
  @override
  ToolDefinition get definition => ToolDefinition(
    name: 'set_date',
    description:
        'Set the value of a date/time picker. Provide the date in ISO 8601 format (YYYY-MM-DD or YYYY-MM-DDTHH:mm:ss).',
    effect: ToolEffect.select,
    parameters: {
      'index': ToolParam(
        type: 'integer',
        description: 'The index of the date picker element',
      ),
      'date': ToolParam(
        type: 'string',
        description:
            'Date in ISO 8601 format, e.g., "2025-03-25" or "2025-03-25T14:30:00"',
      ),
    },
    handler: (args) => throw UnimplementedError('Handled by execute()'),
  );

  @override
  Future<String> execute(Map<String, dynamic> args, ToolContext context) async {
    // Validate parameters
    final index = args['index'] as int?;
    final dateString = args['date'] as String?;

    if (index == null || dateString == null) {
      throw Exception('Missing required parameters: index, date');
    }

    final trimmedDate = dateString.trim();
    if (trimmedDate.isEmpty) {
      throw Exception('Date cannot be empty');
    }

    // Parse ISO 8601 date
    final date = _parseDate(trimmedDate);
    if (date == null) {
      throw Exception(
        'Invalid date format: "$dateString". Use ISO 8601 format (YYYY-MM-DD or YYYY-MM-DDTHH:mm:ss).',
      );
    }

    final target = await context.resolveInteractiveElement(
      index,
      actionName: 'set_date',
    );

    // Verify it's a date picker or generic pressable (date pickers often appear as pressable)
    if (target.type != ElementType.datePicker &&
        target.type != ElementType.pressable &&
        target.type != ElementType.textInput) {
      throw Exception(
        'Element [$index] ${target.label} is not a date picker (type: ${target.type}).',
      );
    }

    // Check widget availability
    if (target.element == null || !target.element!.mounted) {
      throw Exception(
        'Cannot set date on [$index]: no widget reference available.',
      );
    }

    // Try to set the date
    final success = await _performDateSet(target.element!, date, target.label);
    if (!success) {
      throw Exception('Failed to set date on [$index] ${target.label}.');
    }

    return 'Set date to ${_formatDate(date)} on [$index] ${target.label}.';
  }

  DateTime? _parseDate(String dateString) {
    try {
      // Try full ISO 8601 first
      return DateTime.parse(dateString);
    } catch (_) {
      try {
        // Try date only (YYYY-MM-DD)
        return DateTime.parse('${dateString}T00:00:00');
      } catch (_) {
        try {
          // Try common formats
          final parts = dateString.split('-');
          if (parts.length == 3) {
            final year = int.parse(parts[0]);
            final month = int.parse(parts[1]);
            final day = int.parse(
              parts[2].split('T')[0],
            ); // Handle time part if present
            return DateTime(year, month, day);
          }
        } catch (_) {}
        return null;
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<bool> _performDateSet(
    Element element,
    DateTime date,
    String label,
  ) async {
    // Strategy 1: TextField or TextFormField with date input
    TextField? textField;
    void findTextField(Element e) {
      if (textField != null) return;
      if (e.widget is TextField) {
        textField = e.widget as TextField;
        return;
      }
      e.visitChildElements(findTextField);
    }

    findTextField(element);

    if (textField != null) {
      Logger.info(
        'Found TextField, attempting to set date: ${_formatDate(date)}',
      );
      try {
        // Try to update the controller
        final controller = textField!.controller;
        if (controller != null) {
          final formattedDate = _formatDate(date);
          controller.text = formattedDate;
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: formattedDate.length),
          );

          // Trigger onChange callback if present
          final onChanged = textField!.onChanged;
          if (onChanged != null) {
            onChanged(formattedDate);
          }

          // Trigger onSubmitted if present
          final onSubmitted = textField!.onSubmitted;
          if (onSubmitted != null) {
            onSubmitted(formattedDate);
          }

          Logger.info('Successfully set date on TextField: $formattedDate');
          return true;
        }
      } catch (e) {
        Logger.warn('Failed to set date on TextField: $e');
      }
    }

    // Strategy 2: TextFormField (more common for forms)
    TextFormField? textFormField;
    void findTextFormField(Element e) {
      if (textFormField != null) return;
      if (e.widget is TextFormField) {
        textFormField = e.widget as TextFormField;
        return;
      }
      e.visitChildElements(findTextFormField);
    }

    findTextFormField(element);

    if (textFormField != null) {
      Logger.info(
        'Found TextFormField, attempting to set date: ${_formatDate(date)}',
      );
      try {
        final controller = textFormField!.controller;
        if (controller != null) {
          final formattedDate = _formatDate(date);
          controller.text = formattedDate;
          controller.selection = TextSelection.fromPosition(
            TextPosition(offset: formattedDate.length),
          );

          // Trigger onChange callback if present
          final onChanged = textFormField!.onChanged;
          if (onChanged != null) {
            onChanged(formattedDate);
          }

          Logger.info('Successfully set date on TextFormField: $formattedDate');
          return true;
        }
      } catch (e) {
        Logger.warn('Failed to set date on TextFormField: $e');
      }
    }

    // Strategy 3: InkWell or GestureDetector with onTap that might trigger date picker
    // Try to invoke the onTap and simulate date selection
    InkWell? inkWell;
    void findInkWell(Element e) {
      if (inkWell != null) return;
      if (e.widget is InkWell) {
        inkWell = e.widget as InkWell;
        return;
      }
      e.visitChildElements(findInkWell);
    }

    findInkWell(element);

    if (inkWell != null && inkWell!.onTap != null) {
      Logger.info(
        'Found InkWell with onTap, but dialog automation requires manual selection',
      );
      // We could tap to open the dialog, but automated dialog selection is complex
      // For now, we'll return a message explaining the limitation
      return false;
    }

    // Strategy 4: Check for common date picker indicators in the widget tree
    bool hasDateIndicator = false;
    void checkForDateIndicator(Element e) {
      if (hasDateIndicator) return;

      final widget = e.widget;
      if (widget is Icon) {
        final icon = widget.icon;
        if (icon is IconData) {
          // Check for calendar-related icons
          if (icon == Icons.calendar_month ||
              icon == Icons.date_range ||
              icon == Icons.event ||
              icon == Icons.access_time) {
            hasDateIndicator = true;
          }
        }
      }

      // Check Text widgets for date patterns
      if (widget is Text) {
        final text = widget.data ?? '';
        if (text.contains('/') ||
            text.contains('-') ||
            text.contains('AM') ||
            text.contains('PM')) {
          hasDateIndicator = true;
        }
      }

      e.visitChildElements(checkForDateIndicator);
    }

    checkForDateIndicator(element);

    if (hasDateIndicator) {
      Logger.info(
        'Detected date-related UI elements, but requires manual date picker interaction',
      );
      // Date picker detected but dialog automation is complex
      return false;
    }

    // Strategy 5: Try to find State with date-related fields and update them
    bool foundDateState = false;
    void findDateState(Element e) {
      if (foundDateState) return;
      if (e is StatefulElement) {
        final state = e.state;
        // Check for date-related fields using reflection-like access
        try {
          // This is a fallback and may not work in all cases
          final stateFields = state.runtimeType.toString();
          if (stateFields.toLowerCase().contains('date') ||
              stateFields.toLowerCase().contains('time') ||
              stateFields.toLowerCase().contains('calendar')) {
            foundDateState = true;
            Logger.info(
              'Found State with date-related fields, but direct access is limited',
            );
          }
        } catch (_) {}
      }
      e.visitChildElements(findDateState);
    }

    findDateState(element);

    if (foundDateState) {
      // State-based manipulation is complex and fragile
      // Prefer controller-based approaches
      return false;
    }

    Logger.warn('No strategy succeeded for date setting');
    return false;
  }
}
