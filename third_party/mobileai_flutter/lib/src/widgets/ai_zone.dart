import 'package:flutter/widgets.dart';
import '../core/types.dart';
import '../core/zone_registry.dart';
import '../core/block_registry.dart';
import 'rich_content_renderer.dart';

class AIZone extends StatefulWidget {
  final String id;
  final bool allowHighlight;
  final bool allowGuide;
  final bool allowSimplify;
  final bool allowInjectBlock;
  @Deprecated('Use allowInjectBlock')
  final bool allowInjectCard;
  final bool interventionEligible;
  final bool proactiveIntervention;
  final List<BlockDefinition> blocks;
  final String? description;
  final Widget child;

  const AIZone({
    super.key,
    required this.id,
    this.allowHighlight = true,
    this.allowGuide = true,
    this.allowSimplify = false,
    this.allowInjectBlock = false,
    this.allowInjectCard = false,
    this.interventionEligible = false,
    this.proactiveIntervention = false,
    this.blocks = const [],
    this.description,
    required this.child,
  });

  @override
  State<AIZone> createState() => _AIZoneState();
}

class _AIZoneState extends State<AIZone> {
  final GlobalKey _zoneKey = GlobalKey();
  bool _simplified = false;
  Object? _injectedContent;

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(AiZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      globalZoneRegistry.unregister(oldWidget.id);
      _register();
    } else {
      _register();
    }
  }

  @override
  void dispose() {
    globalZoneRegistry.unregister(widget.id);
    super.dispose();
  }

  void _register() {
    for (final block in widget.blocks) {
      globalBlockRegistry.register(block);
    }
    globalZoneRegistry.register(
      AiZoneConfig(
        id: widget.id,
        allowHighlight: widget.allowHighlight,
        allowGuide: widget.allowGuide,
        allowSimplify: widget.allowSimplify,
        allowInjectBlock: widget.allowInjectBlock,
        allowInjectCard: widget.allowInjectCard,
        interventionEligible: widget.interventionEligible,
        proactiveIntervention: widget.proactiveIntervention,
        blocks: widget.blocks,
        description: widget.description,
      ),
      _zoneKey,
    );
    final zone = globalZoneRegistry.getZone(widget.id);
    if (zone != null) {
      zone.controller = _AIZoneController(
        simplify: () => mounted ? setState(() => _simplified = true) : null,
        restore: () => mounted
            ? setState(() {
                _simplified = false;
                _injectedContent = null;
              })
            : null,
        renderBlock: (content) => mounted ? setState(() => _injectedContent = content) : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _zoneKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_simplified) widget.child,
          if (_injectedContent != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: RichContentRenderer(
                content: _injectedContent,
                placement: BlockPlacement.zone,
              ),
            ),
        ],
      ),
    );
  }
}

class _AIZoneController {
  final VoidCallback simplify;
  final VoidCallback restore;
  final void Function(Object content) renderBlock;

  _AIZoneController({
    required this.simplify,
    required this.restore,
    required this.renderBlock,
  });
}

@Deprecated('Use AIZone instead.')
typedef AiZone = AIZone;
