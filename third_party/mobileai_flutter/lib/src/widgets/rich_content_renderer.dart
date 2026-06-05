import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/block_registry.dart';
import '../core/types.dart';

class RichContentRenderer extends StatelessWidget {
  final Object? content;
  final BlockPlacement placement;

  const RichContentRenderer({
    super.key,
    required this.content,
    this.placement = BlockPlacement.chat,
  });

  @override
  Widget build(BuildContext context) {
    final nodes = normalizeRichContent(content, richContentToPlainText(content));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: nodes.map((node) {
        if (node is AiTextNode) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(node.text),
          );
        }
        if (node is AiImageNode) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Image.memory(
                  base64Decode(node.base64),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.white.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        if (node is AiBlockNode) {
          final definition = globalBlockRegistry.get(node.blockType);
          if (definition == null || !definition.allowedPlacements.contains(placement)) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: definition.builder(context, node.props),
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }
}
