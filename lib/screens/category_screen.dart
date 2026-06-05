import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/seed_data.dart';
import '../providers/cart_provider.dart';
import '../providers/data_provider.dart';

class CategoryScreen extends ConsumerWidget {
  final String categoryId;
  const CategoryScreen({Key? key, required this.categoryId}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Synchronously fetch category metadata since we assume it's small/cached from home screen
    final cat = SeedData.categories.firstWhere((c) => c.id == categoryId, 
      orElse: () => const Category(id: 'unknown', name: 'Unknown', icon: '❓'));
    
    final productsAsync = ref.watch(categoryProductsProvider(categoryId));

    return Scaffold(
      appBar: AppBar(title: Text('${cat.icon} ${cat.name}')),
      body: productsAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('No products found'));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.60,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final prod = products[index];
              return _buildProductCard(context, ref, prod);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error loading products: $e')),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, WidgetRef ref, Product prod) {
    return GestureDetector(
      onTap: () => context.push('/product/${prod.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.grey.shade100,
                child: Image.network(prod.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 50, color: Colors.grey)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(prod.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text('\$${prod.price}', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 10, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text('${prod.rating}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        ref.read(cartProvider.notifier).addItem(prod);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${prod.name} added to Cart!')));
                      },
                      child: const Text('Add to Cart', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
