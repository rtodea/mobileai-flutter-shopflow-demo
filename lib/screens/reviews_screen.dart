import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/data_provider.dart';

class ReviewsScreen extends ConsumerStatefulWidget {
  final String productId;

  const ReviewsScreen({Key? key, required this.productId}) : super(key: key);

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<Review> _allReviews = [];
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore(); // Initial load handled by manual Riverpod fetch inside _loadMore
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    final args = (productId: widget.productId, page: _currentPage);
    try {
      final paginated = await ref.read(reviewsProvider(args).future);
      setState(() {
        _allReviews.addAll(paginated.reviews);
        _hasMore = paginated.hasMore;
        _currentPage++;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer Reviews')),
      body: _allReviews.isEmpty && _isLoadingMore
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _allReviews.length + (_hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(height: 32),
              itemBuilder: (context, index) {
                if (index == _allReviews.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final review = _allReviews[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(review.author, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("${review.date.toLocal()}".split(' ')[0], style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(5, (starIndex) {
                        return Icon(
                          starIndex < review.rating.round() ? Icons.star : Icons.star_border,
                          size: 16,
                          color: Colors.amber,
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(review.text, style: const TextStyle(fontSize: 15, height: 1.4)),
                  ],
                );
              },
            ),
    );
  }
}
