import 'types.dart';

class DataRegistry {
  final Map<String, DataDefinition> _dataSources = {};
  final Set<void Function()> _listeners = {};

  void register(DataDefinition source) {
    _dataSources[source.name] = source;
    _notify();
  }

  void unregister(String name) {
    _dataSources.remove(name);
    _notify();
  }

  DataDefinition? get(String name) => _dataSources[name];

  List<DataDefinition> getAll() => _dataSources.values.toList();

  void clear() {
    _dataSources.clear();
    _notify();
  }

  void Function() onChange(void Function() listener) {
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  void _notify() {
    for (final listener in _listeners) {
      listener();
    }
  }
}

final dataRegistry = DataRegistry();
