import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/seed_data.dart';
import '../providers/cart_provider.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategoryId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredProducts = _rankedProducts();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search products...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear, color: Colors.white),
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
            ),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: (val) => setState(() => _searchQuery = val),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _selectedCategoryId == null,
                    onSelected: (_) => setState(() => _selectedCategoryId = null),
                  ),
                  const SizedBox(width: 8),
                  ...SeedData.categories.map((c) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(c.name),
                        selected: _selectedCategoryId == c.id,
                        onSelected: (_) => setState(() => _selectedCategoryId = c.id),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          Expanded(
            child: filteredProducts.isEmpty
                ? const Center(child: Text('No products found matching your search.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredProducts.length,
                    separatorBuilder:
                        (context, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final prod = filteredProducts[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => context.push('/product/${prod.id}'),
                          child: Row(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                color: Colors.grey.shade100,
                                child: Image.network(prod.imageUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, size: 40, color: Colors.grey)),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Category: ${_categoryName(prod.categoryId)}',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('\$${prod.price}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.star, size: 14, color: Colors.amber),
                                              Text(' ${prod.rating}'),
                                            ],
                                          ),
                                          SizedBox(
                                            height: 30,
                                            child: ElevatedButton(
                                              onPressed: () {
                                                ref.read(cartProvider.notifier).addItem(prod);
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to cart')));
                                              },
                                              child: const Text('Add', style: TextStyle(fontSize: 12)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _categoryName(String categoryId) {
    return SeedData.categories
        .firstWhere(
          (category) => category.id == categoryId,
          orElse: () => const Category(id: 'unknown', name: 'Unknown', icon: '•'),
        )
        .name;
  }

  List<Product> _rankedProducts() {
    final queryTokens = _tokenizeForSearch(_searchQuery);
    final normalizedQuery = _normalizeSearchText(_searchQuery);

    final scoredProducts = SeedData.products
        .where((product) {
          return _selectedCategoryId == null || product.categoryId == _selectedCategoryId;
        })
        .map((product) => (
              product: product,
              score: _scoreProduct(product, queryTokens, normalizedQuery),
            ))
        .where((entry) => queryTokens.isEmpty || entry.score > 0)
        .toList(growable: false);

    scoredProducts.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      final ratingCompare = b.product.rating.compareTo(a.product.rating);
      if (ratingCompare != 0) {
        return ratingCompare;
      }
      return a.product.name.compareTo(b.product.name);
    });

    return scoredProducts.map((entry) => entry.product).toList(growable: false);
  }

  int _scoreProduct(
    Product product,
    List<String> queryTokens,
    String normalizedQuery,
  ) {
    if (queryTokens.isEmpty) {
      return 1;
    }

    final searchableText = _normalizeSearchText(
      '${product.name} ${product.description} ${_categoryName(product.categoryId)}',
    );
    final productTokens = _tokenizeForSearch(searchableText);
    final productTokenSet = productTokens.toSet();
    var score = 0;

    if (normalizedQuery.isNotEmpty && searchableText.contains(normalizedQuery)) {
      score += 120;
    }

    for (final token in queryTokens) {
      if (productTokenSet.contains(token)) {
        score += 20;
        continue;
      }

      final partialMatch = productTokens.any(
        (candidate) =>
            candidate.length >= 3 &&
            token.length >= 3 &&
            (candidate.contains(token) || token.contains(candidate)),
      );
      if (partialMatch) {
        score += 10;
      }
    }

    if (_normalizeSearchText(product.name).contains(normalizedQuery) &&
        normalizedQuery.isNotEmpty) {
      score += 40;
    }

    return score;
  }

  List<String> _tokenizeForSearch(String text) {
    final normalized = _normalizeSearchText(text);
    if (normalized.isEmpty) {
      return const <String>[];
    }

    return normalized
        .split(' ')
        .map(_canonicalizeSearchToken)
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  String _normalizeSearchText(String text) {
    var normalized = text.toLowerCase();
    normalized = normalized.replaceAll(
      RegExp(r'\b(t[\s-]?shirt|tee[\s-]?shirt|tee)\b'),
      ' tshirt ',
    );
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  String _canonicalizeSearchToken(String token) {
    switch (token) {
      case 'shirt':
      case 't':
      case 'tee':
        return 'tshirt';
      default:
        return token;
    }
  }
}
