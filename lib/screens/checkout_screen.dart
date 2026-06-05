import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/cart_provider.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  int _currentStep = 0;
  bool _isExpressDelivery = false;
  bool _acceptTerms = false;
  String _paymentMethod = 'card';

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () async {
          if (_currentStep < 2) {
            setState(() => _currentStep += 1);
          } else {
            if (!_acceptTerms) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please accept terms and conditions')),
              );
              return;
            }
            
            showDialog(
              context: context, 
              barrierDismissible: false,
              builder: (_) => const Center(child: CircularProgressIndicator())
            );
            
            await Future.delayed(const Duration(milliseconds: 1500));
            Navigator.of(context).pop();

            // Success
            ref.read(cartProvider.notifier).clear();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Order Placed Successfully!')),
            );
            context.go('/home');
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          }
        },
        steps: [
          Step(
            title: const Text('Delivery Details'),
            content: Column(
              children: [
                const TextField(decoration: InputDecoration(labelText: 'Full Name')),
                const TextField(decoration: InputDecoration(labelText: 'Address')),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Express Delivery (+\$10)'),
                  value: _isExpressDelivery,
                  onChanged: (val) => setState(() => _isExpressDelivery = val),
                ),
              ],
            ),
            isActive: _currentStep >= 0,
          ),
          Step(
            title: const Text('Payment Method'),
            content: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('Credit Card'),
                  value: 'card',
                  groupValue: _paymentMethod,
                  onChanged: (val) => setState(() => _paymentMethod = val!),
                ),
                RadioListTile<String>(
                  title: const Text('PayPal'),
                  value: 'paypal',
                  groupValue: _paymentMethod,
                  onChanged: (val) => setState(() => _paymentMethod = val!),
                ),
              ],
            ),
            isActive: _currentStep >= 1,
          ),
          Step(
            title: const Text('Confirm Order'),
            content: Column(
              children: [
                Text('Total: \$${(cartState.total + (_isExpressDelivery ? 10 : 0)).toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('I accept the Terms and Conditions'),
                  value: _acceptTerms,
                  onChanged: (val) => setState(() => _acceptTerms = val!),
                )
              ],
            ),
            isActive: _currentStep >= 2,
          ),
        ],
      ),
    );
  }
}
