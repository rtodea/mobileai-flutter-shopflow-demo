import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/seed_data.dart';
import '../providers/cart_provider.dart';
import '../providers/data_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final flashDealsAsync = ref.watch(flashDealsProvider);
    final newArrivalsAsync = ref.watch(productsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('ShopFlow Explorer', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade300],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.white.withOpacity(0.3)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
             child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   const Text('Shop by Category', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 16),
                   categoriesAsync.when(
                     data: (categories) => SizedBox(
                       height: 110,
                       child: ListView.builder(
                         scrollDirection: Axis.horizontal,
                         itemCount: categories.length,
                         itemBuilder: (context, index) {
                           final cat = categories[index];
                           return GestureDetector(
                             onTap: () => context.push('/category/${cat.id}'),
                             child: Container(
                               width: 90,
                               margin: const EdgeInsets.only(right: 16),
                               decoration: BoxDecoration(
                                 color: Colors.white,
                                 borderRadius: BorderRadius.circular(16),
                                 boxShadow: const [
                                   BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))
                                 ],
                               ),
                               child: Column(
                                 mainAxisAlignment: MainAxisAlignment.center,
                                 children: [
                                   Text(cat.icon, style: const TextStyle(fontSize: 36)),
                                   const SizedBox(height: 8),
                                   Text(cat.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                 ],
                               ),
                             ),
                           );
                         },
                       ),
                     ),
                     loading: () => const SizedBox(height: 110, child: Center(child: CircularProgressIndicator())),
                     error: (e, st) => Text('Error: $e'),
                   ),
                   const SizedBox(height: 32),
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       const Text('Flash Deals ⚡', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                       TextButton(onPressed: () {}, child: const Text('View All')),
                     ],
                   ),
                   const SizedBox(height: 8),
                   flashDealsAsync.when(
                     data: (deals) => SizedBox(
                       height: 260,
                       child: ListView.builder(
                         scrollDirection: Axis.horizontal,
                         itemCount: deals.length,
                         itemBuilder: (context, index) {
                           final prod = deals[index];
                           return _buildProductCard(context, ref, prod, width: 160);
                         },
                       ),
                     ),
                     loading: () => const SizedBox(height: 260, child: Center(child: CircularProgressIndicator())),
                     error: (e, st) => Text('Error: $e'),
                   ),
                   const SizedBox(height: 24),
                   const Text('New Arrivals', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 16),
                 ],
               ),
             ),
          ),
          newArrivalsAsync.when(
            data: (products) => SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.60,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final prod = products[index];
                    return _buildProductCard(context, ref, prod);
                  },
                  childCount: products.length,
                ),
              ),
            ),
            loading: () => const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()))),
            error: (e, st) => SliverToBoxAdapter(child: Text('Error: $e')),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, WidgetRef ref, Product prod, {double? width}) {
    return GestureDetector(
      onTap: () => context.push('/product/${prod.id}'),
      child: Container(
        width: width,
        margin: width != null ? const EdgeInsets.only(right: 16) : null,
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
