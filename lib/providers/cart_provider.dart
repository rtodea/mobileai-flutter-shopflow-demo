import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/seed_data.dart';

class CartItem {
  final Product product;
  int quantity;
  final String? color;

  CartItem({required this.product, this.quantity = 1, this.color});
  
  double get total => product.price * quantity;
}

class CartState {
  final List<CartItem> items;
  final String? promoCode;
  final double discountRate; // e.g. 0.10 for 10%

  CartState({
    this.items = const [],
    this.promoCode,
    this.discountRate = 0.0,
  });

  double get subtotal => items.fold(0, (sum, item) => sum + item.total);
  double get discountAmount => subtotal * discountRate;
  double get total => subtotal - discountAmount;

  CartState copyWith({
    List<CartItem>? items,
    String? promoCode,
    double? discountRate,
  }) {
    return CartState(
      items: items ?? this.items,
      promoCode: promoCode ?? this.promoCode,
      discountRate: discountRate ?? this.discountRate,
    );
  }
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => CartState();

  void addItem(Product product, {String? color}) {
    final items = List<CartItem>.from(state.items);
    final index = items.indexWhere((i) => i.product.id == product.id && i.color == color);
    
    if (index >= 0) {
      items[index] = CartItem(
        product: product, 
        quantity: items[index].quantity + 1, 
        color: color
      );
    } else {
      items.add(CartItem(product: product, color: color));
    }
    
    state = state.copyWith(items: items);
  }

  void removeItem(String productId, String? color) {
    final items = List<CartItem>.from(state.items);
    items.removeWhere((i) => i.product.id == productId && i.color == color);
    state = state.copyWith(items: items);
  }

  void updateQuantity(String productId, String? color, int newQuantity) {
    if (newQuantity <= 0) {
      removeItem(productId, color);
      return;
    }
    final items = List<CartItem>.from(state.items);
    final index = items.indexWhere((i) => i.product.id == productId && i.color == color);
    if (index >= 0) {
      items[index] = CartItem(
        product: items[index].product, 
        quantity: newQuantity, 
        color: color
      );
      state = state.copyWith(items: items);
    }
  }

  bool applyPromoCode(String code) {
    if (code.toUpperCase() == 'DISCOUNT10') {
      state = state.copyWith(promoCode: code, discountRate: 0.10);
      return true;
    } else if (code.toUpperCase() == 'HALFOFF') {
      state = state.copyWith(promoCode: code, discountRate: 0.50);
      return true;
    }
    return false;
  }
  
  void removePromoCode() {
    state = state.copyWith(promoCode: null, discountRate: 0.0);
  }
  
  void clear() {
    state = CartState();
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(() {
  return CartNotifier();
});
