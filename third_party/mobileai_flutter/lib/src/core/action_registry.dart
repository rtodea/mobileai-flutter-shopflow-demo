import 'types.dart';

class McpToolDeclaration {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  McpToolDeclaration({
    required this.name,
    required this.description,
    required this.inputSchema,
  });
}

/// A central registry for all actions registered via `AiAction` widgets.
/// This acts as the single source of truth for:
/// 1. The in-app AI Agent (AgentRuntime)
/// 2. The MCP Server (external agents)
/// 3. iOS App Intents (Siri)
/// 4. Android AppFunctions (Gemini)
class ActionRegistry {
  final Map<String, ActionDefinition> _actions = {};
  final Set<void Function()> _listeners = {};

  /// Register a new action definition
  void register(ActionDefinition action) {
    _actions[action.name] = action;
    _notify();
  }

  /// Unregister an action by name
  void unregister(String name) {
    _actions.remove(name);
    _notify();
  }

  /// Get a specific action by name
  ActionDefinition? getAction(String name) {
    return _actions[name];
  }

  /// Get all registered actions
  List<ActionDefinition> getAll() {
    return _actions.values.toList();
  }

  /// Clear all registered actions (useful for testing)
  void clear() {
    _actions.clear();
    _notify();
  }

  /// Subscribe to changes (e.g. when a new screen mounts and registers actions).
  /// Useful for the MCP server to re-announce tools.
  void Function() onChange(void Function() listener) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  /// Serialize all actions as strictly-typed MCP tool declarations
  List<McpToolDeclaration> toMcpTools() {
    return getAll().map((a) {
      return McpToolDeclaration(
        name: a.name,
        description: a.description,
        inputSchema: _buildInputSchema(a.parameters),
      );
    }).toList();
  }

  Map<String, dynamic> _buildInputSchema(Map<String, dynamic> params) {
    final properties = <String, dynamic>{};
    final requiredProps = <String>[];

    for (final entry in params.entries) {
      final key = entry.key;
      final val = entry.value;

      if (val is String) {
        // Backward compatibility: passing a string means it's a required string param.
        properties[key] = {
          'type': 'string',
          'description': val,
        };
        requiredProps.push(key);
      } else if (val is ActionParameterDef) {
        // Strict parameter definition
        properties[key] = {
          'type': val.type,
          'description': val.description,
        };
        if (val.enumValues != null) {
          properties[key]['enum'] = val.enumValues;
        }
        if (val.required) {
          requiredProps.add(key);
        }
      }
    }

    return {
      'type': 'object',
      'properties': properties,
      'required': requiredProps,
    };
  }

  void _notify() {
    for (var listener in _listeners) {
      listener();
    }
  }
}

// Export a singleton instance.
// This allows background channels (like App Intents bridging) to access actions
// even if the widget tree hasn't been fully built.
final actionRegistry = ActionRegistry();

extension ListPush<T> on List<T> {
  void push(T value) => add(value);
}
