import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/seed_data.dart';

// Simulates network delay
Future<void> _mockNetworkDelay([int ms = 800]) => Future.delayed(Duration(milliseconds: ms));

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  await _mockNetworkDelay(500);
  return SeedData.categories;
});

final flashDealsProvider = FutureProvider<List<Product>>((ref) async {
  await _mockNetworkDelay(800);
  return SeedData.products.where((p) => p.isFlashDeal).toList();
});

final productsProvider = FutureProvider<List<Product>>((ref) async {
  await _mockNetworkDelay(1200);
  return SeedData.products;
});

final categoryProductsProvider = FutureProvider.family<List<Product>, String>((ref, categoryId) async {
  await _mockNetworkDelay(1000);
  return SeedData.products.where((p) => p.categoryId == categoryId).toList();
});

final productDetailProvider = FutureProvider.family<Product, String>((ref, productId) async {
  await _mockNetworkDelay(600);
  return SeedData.products.firstWhere((p) => p.id == productId, orElse: () => SeedData.products.first);
});

final searchProvider = FutureProvider.family<List<Product>, String>((ref, query) async {
  await _mockNetworkDelay(700);
  if (query.isEmpty) return SeedData.products;
  final normalizedQuery = query.trim().toLowerCase();
  return SeedData.products.where((product) {
    final haystack = '${product.name} ${product.description}'.toLowerCase();
    return haystack.contains(normalizedQuery);
  }).toList(growable: false);
});

// Reviews Pagination Mock
class Review {
  final String id;
  final String author;
  final double rating;
  final String text;
  final DateTime date;

  Review({required this.id, required this.author, required this.rating, required this.text, required this.date});
}

class PaginatedReviews {
  final List<Review> reviews;
  final bool hasMore;
  PaginatedReviews(this.reviews, this.hasMore);
}

final reviewsProvider = FutureProvider.family<PaginatedReviews, ({String productId, int page})>((ref, args) async {
  await _mockNetworkDelay(1000); // 1 second load per page
  
  final pageSize = 10;
  final totalReviews = 35; // Mock total
  
  if (args.page * pageSize >= totalReviews) {
    return PaginatedReviews([], false);
  }
  
  final count = ((args.page + 1) * pageSize > totalReviews) ? (totalReviews % (args.page * pageSize)) : pageSize;
  final reviews = List.generate(count, (i) {
    final index = args.page * pageSize + i;
    return Review(
      id: '${args.productId}_rev_$index',
      author: 'User ${index + 1}',
      rating: 4.0 + (index % 2),
      text: 'This is an amazing product! Really enjoyed using it. Review #$index',
      date: DateTime.now().subtract(Duration(days: index * 2)),
    );
  });
  
  return PaginatedReviews(reviews, (args.page + 1) * pageSize < totalReviews);
});
