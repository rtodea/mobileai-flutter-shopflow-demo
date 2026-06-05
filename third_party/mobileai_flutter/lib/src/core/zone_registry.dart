import 'package:flutter/widgets.dart';
import 'types.dart';
import '../utils/logger.dart';

enum ZoneAction { highlight, hint, simplify, card }

class ZoneRegistry {
  final Map<String, RegisteredZone> _zones = {};

  void register(AiZoneConfig config, GlobalKey key) {
    if (_zones.containsKey(config.id)) {
      Logger.warn('Zone ID "${config.id}" is already registered on this screen. Overwriting.');
    }
    _zones[config.id] = RegisteredZone(config: config, key: key);
  }

  void unregister(String id) {
    _zones.remove(id);
  }

  RegisteredZone? getZone(String id) {
    return _zones[id];
  }

  List<RegisteredZone> getAll() {
    return _zones.values.toList();
  }

  bool isActionAllowed(String zoneId, ZoneAction action) {
    final zone = getZone(zoneId);
    if (zone == null) return false;

    switch (action) {
      case ZoneAction.highlight:
        // By default, guide/highlight might be the same
        return zone.config.allowGuide;
      case ZoneAction.hint:
        return zone.config.allowGuide;
      case ZoneAction.simplify:
        return zone.config.allowSimplify;
      case ZoneAction.card:
        return zone.config.allowInjectBlock || zone.config.allowInjectCard;
    }
  }
}

// Global registry instance shared across the Agent session
final globalZoneRegistry = ZoneRegistry();
