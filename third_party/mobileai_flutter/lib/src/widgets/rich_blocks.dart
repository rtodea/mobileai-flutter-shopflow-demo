import 'package:flutter/material.dart';

import '../core/action_bridge.dart';
import '../core/block_registry.dart';
import '../core/types.dart';
import '../theme/rich_ui_theme.dart';

class CardSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const CardSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.elevatedSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.border),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;

  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    return Text(
      text,
      style: TextStyle(
        color: theme.primaryText,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class BadgeRow extends StatelessWidget {
  final List<String> badges;

  const BadgeRow({super.key, required this.badges});

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: badges
          .map((badge) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: theme.primaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class PriceTag extends StatelessWidget {
  final String value;

  const PriceTag({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    return Text(
      value,
      style: TextStyle(
        color: theme.accent,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class MediaFrame extends StatelessWidget {
  final String? imageUrl;
  final double height;

  const MediaFrame({
    super.key,
    this.imageUrl,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl?.isNotEmpty == true
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _placeholder(theme),
            )
          : _placeholder(theme),
    );
  }

  Widget _placeholder(RichUiSurfaceTheme theme) {
    return Center(
      child: Icon(
        Icons.image_outlined,
        color: theme.secondaryText,
        size: 28,
      ),
    );
  }
}

class MetaRow extends StatelessWidget {
  final List<String> items;

  const MetaRow({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items
          .where((item) => item.trim().isNotEmpty)
          .map(
            (item) => Text(
              item,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
          .toList(),
    );
  }
}

class ActionRow extends StatelessWidget {
  final List<Widget> children;

  const ActionRow({
    super.key,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: children,
    );
  }
}

class FieldRow extends StatelessWidget {
  final String label;
  final String value;

  const FieldRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: theme.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(color: theme.primaryText),
          ),
        ),
      ],
    );
  }
}

class FactCard extends StatelessWidget {
  final String title;
  final String body;

  const FactCard({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    return CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(color: theme.secondaryText, height: 1.45)),
        ],
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final String title;
  final String? description;
  final String? imageUrl;
  final String? price;
  final List<String> badges;
  final List<String> meta;
  final String? primaryActionId;
  final String? primaryActionLabel;

  const ProductCard({
    super.key,
    required this.title,
    this.description,
    this.imageUrl,
    this.price,
    this.badges = const [],
    this.meta = const [],
    this.primaryActionId,
    this.primaryActionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    final bridge = ActionBridge.maybeOf(context);
    return CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl?.isNotEmpty == true) ...[
            MediaFrame(imageUrl: imageUrl),
            const SizedBox(height: 14),
          ],
          SectionTitle(title),
          if (description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(description!, style: TextStyle(color: theme.secondaryText, height: 1.45)),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 10),
            MetaRow(items: meta),
          ],
          if (price?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            PriceTag(value: price!),
          ],
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 12),
            BadgeRow(badges: badges),
          ],
          if (primaryActionId != null && primaryActionLabel != null && bridge != null) ...[
            const SizedBox(height: 14),
            ActionRow(
              children: [
                FilledButton(
                  onPressed: () => bridge.dispatch(primaryActionId!),
                  child: Text(primaryActionLabel!),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ActionCard extends StatelessWidget {
  final String title;
  final String body;
  final String? actionId;
  final String? actionLabel;

  const ActionCard({
    super.key,
    required this.title,
    required this.body,
    this.actionId,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    final bridge = ActionBridge.maybeOf(context);
    return CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(color: theme.secondaryText, height: 1.45)),
          if (actionId != null && actionLabel != null && bridge != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => bridge.dispatch(actionId!),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class ComparisonCard extends StatelessWidget {
  final String title;
  final List<ComparisonCardItem> items;

  const ComparisonCard({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    return CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.imageUrl?.isNotEmpty == true) ...[
                        MediaFrame(
                          imageUrl: item.imageUrl,
                          height: 132,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    color: theme.primaryText,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                if (item.subtitle?.isNotEmpty == true) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    item.subtitle!,
                                    style: TextStyle(
                                      color: theme.secondaryText,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (item.price?.isNotEmpty == true) ...[
                            const SizedBox(width: 12),
                            PriceTag(value: item.price!),
                          ],
                        ],
                      ),
                      if (item.summary?.isNotEmpty == true) ...[
                        const SizedBox(height: 10),
                        Text(
                          item.summary!,
                          style: TextStyle(
                            color: theme.secondaryText,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (item.badges.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        BadgeRow(badges: item.badges),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ComparisonCardItem {
  final String title;
  final String? subtitle;
  final String? price;
  final String? summary;
  final String? imageUrl;
  final List<String> badges;

  const ComparisonCardItem({
    required this.title,
    this.subtitle,
    this.price,
    this.summary,
    this.imageUrl,
    this.badges = const [],
  });
}

class FormCard extends StatelessWidget {
  final String title;
  final String? description;
  final List<Map<String, String>> fields;
  final String? submitActionId;
  final String submitLabel;

  const FormCard({
    super.key,
    required this.title,
    this.description,
    this.fields = const [],
    this.submitActionId,
    this.submitLabel = 'Submit',
  });

  @override
  Widget build(BuildContext context) {
    final theme = RichUiThemeScope.of(context).chat;
    final bridge = ActionBridge.maybeOf(context);
    return CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(title),
          if (description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(description!, style: TextStyle(color: theme.secondaryText, height: 1.45)),
          ],
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...fields.map(
              (field) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FieldRow(
                  label: field['label'] ?? '',
                  value: field['value'] ?? '',
                ),
              ),
            ),
          ],
          if (submitActionId != null && bridge != null) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => bridge.dispatch(submitActionId!),
              child: Text(submitLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  final String title;
  final String description;

  const InfoCard({
    super.key,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return FactCard(title: title, body: description);
  }
}

class ReviewSummary extends StatelessWidget {
  final String title;
  final String? description;
  final String? price;
  final String? imageUrl;

  const ReviewSummary({
    super.key,
    required this.title,
    this.description,
    this.price,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return ProductCard(
      title: title,
      description: description,
      price: price,
      imageUrl: imageUrl,
    );
  }
}

final factCardDefinition = BlockDefinition(
  name: 'FactCard',
  builder: (context, props) => FactCard(
    title: '${props['title'] ?? 'Fact'}',
    body: '${props['body'] ?? props['description'] ?? ''}',
  ),
  allowedPlacements: const [BlockPlacement.chat, BlockPlacement.zone],
  interventionEligible: true,
  interventionType: BlockInterventionType.contextualHelp,
);

final productCardDefinition = BlockDefinition(
  name: 'ProductCard',
  builder: (context, props) => ProductCard(
    title: '${props['title'] ?? props['name'] ?? 'Product'}',
    description: props['description']?.toString(),
    imageUrl: props['imageUrl']?.toString() ?? props['image']?.toString(),
    price: props['price']?.toString(),
    badges: (props['badges'] as List?)?.map((item) => '$item').toList() ?? const [],
    meta: (props['meta'] as List?)?.map((item) => '$item').toList() ?? const [],
    primaryActionId: props['primaryActionId']?.toString(),
    primaryActionLabel: props['primaryActionLabel']?.toString(),
  ),
  allowedPlacements: const [BlockPlacement.chat, BlockPlacement.zone],
  interventionEligible: true,
  interventionType: BlockInterventionType.decisionSupport,
);

final actionCardDefinition = BlockDefinition(
  name: 'ActionCard',
  builder: (context, props) => ActionCard(
    title: '${props['title'] ?? 'Next Step'}',
    body: '${props['body'] ?? props['description'] ?? ''}',
    actionId: props['actionId']?.toString(),
    actionLabel: props['actionLabel']?.toString(),
  ),
  allowedPlacements: const [BlockPlacement.chat, BlockPlacement.zone],
  interventionEligible: true,
);

final comparisonCardDefinition = BlockDefinition(
  name: 'ComparisonCard',
  builder: (context, props) => ComparisonCard(
    title: '${props['title'] ?? 'Comparison'}',
    items: (props['items'] as List?)
            ?.map(_parseComparisonCardItem)
            .whereType<ComparisonCardItem>()
            .toList() ??
        const <ComparisonCardItem>[],
  ),
  allowedPlacements: const [BlockPlacement.chat, BlockPlacement.zone],
  interventionEligible: true,
  interventionType: BlockInterventionType.decisionSupport,
);

final formCardDefinition = BlockDefinition(
  name: 'FormCard',
  builder: (context, props) => FormCard(
    title: '${props['title'] ?? 'Form'}',
    description: props['description']?.toString(),
    fields: (props['fields'] as List?)
            ?.map((item) => Map<String, String>.from((item as Map).map((key, value) => MapEntry('$key', '$value'))))
            .toList() ??
        const [],
    submitActionId: props['submitActionId']?.toString(),
    submitLabel: '${props['submitLabel'] ?? 'Submit'}',
  ),
  allowedPlacements: const [BlockPlacement.chat, BlockPlacement.zone],
  interventionEligible: true,
  interventionType: BlockInterventionType.contextualHelp,
);

void registerBuiltInBlocks() {
  globalBlockRegistry.register(factCardDefinition);
  globalBlockRegistry.register(productCardDefinition);
  globalBlockRegistry.register(actionCardDefinition);
  globalBlockRegistry.register(comparisonCardDefinition);
  globalBlockRegistry.register(formCardDefinition);
}

ComparisonCardItem? _parseComparisonCardItem(Object? raw) {
  if (raw is! Map) {
    return null;
  }

  final item = Map<String, dynamic>.from(raw);
  final title = '${item['title'] ?? item['name'] ?? item['label'] ?? ''}'.trim();
  final subtitle = '${item['subtitle'] ?? ''}'.trim();
  final price = '${item['price'] ?? item['value'] ?? ''}'.trim();
  final summary = '${item['summary'] ?? item['description'] ?? ''}'.trim();
  final imageUrl = '${item['imageUrl'] ?? item['image'] ?? ''}'.trim();
  final badges = (item['badges'] as List?)
          ?.map((badge) => '$badge'.trim())
          .where((badge) => badge.isNotEmpty)
          .toList() ??
      const <String>[];

  if (title.isEmpty &&
      subtitle.isEmpty &&
      price.isEmpty &&
      summary.isEmpty &&
      imageUrl.isEmpty &&
      badges.isEmpty) {
    return null;
  }

  return ComparisonCardItem(
    title: title.isNotEmpty ? title : 'Option',
    subtitle: subtitle.isNotEmpty ? subtitle : null,
    price: price.isNotEmpty ? price : null,
    summary: summary.isNotEmpty ? summary : null,
    imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
    badges: badges,
  );
}
