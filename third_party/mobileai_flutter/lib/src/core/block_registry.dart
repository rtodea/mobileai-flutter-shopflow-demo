import 'types.dart';

class BlockRegistry {
  final Map<String, BlockDefinition> _blocks = {};

  void register(BlockDefinition definition) {
    _blocks[definition.name] = definition;
  }

  void unregister(String name) {
    _blocks.remove(name);
  }

  BlockDefinition? get(String name) => _blocks[name];

  List<BlockDefinition> getAll() => _blocks.values.toList();

  List<BlockDefinition> getForPlacement(BlockPlacement placement) {
    return _blocks.values
        .where((definition) => definition.allowedPlacements.contains(placement))
        .toList();
  }

  List<BlockDefinition> getAllowedForZone(AiZoneConfig zone) {
    if (zone.blocks.isEmpty) {
      return getForPlacement(BlockPlacement.zone);
    }
    return zone.blocks
        .where((definition) => definition.allowedPlacements.contains(BlockPlacement.zone))
        .toList();
  }
}

final globalBlockRegistry = BlockRegistry();
