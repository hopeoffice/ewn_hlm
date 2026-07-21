import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.cart.isEmpty) {
      return const Center(child: Text('ጋሪዎ ባዶ ነው'));
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: app.cart.length,
            itemBuilder: (context, i) {
              final item = app.cart[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: item.image.isNotEmpty
                      ? Image.network(item.image, width: 56, height: 56, fit: BoxFit.cover)
                      : const Icon(Icons.image_not_supported),
                  title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${item.price.toStringAsFixed(0)} ብር'
                      '${item.color != null ? ' • ${item.color}' : ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => app.updateQty(item.id, item.color, item.qty - 1),
                      ),
                      Text('${item.qty}'),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => app.updateQty(item.id, item.color, item.qty + 1),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('ጠቅላላ: ${app.cartTotal.toStringAsFixed(0)} ብር',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brand),
                  onPressed: () {
                    if (!app.isAuthenticated) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('ትዕዛዝ ለመላክ እባክዎ ይግቡ')));
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                    );
                  },
                  child: const Text('ትዕዛዝ ይላኩ', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
