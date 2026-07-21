import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!app.isAuthenticated) {
      return const Center(child: Text('ትዕዛዞችዎን ለማየት ይግቡ'));
    }
    if (app.orders.isEmpty) {
      return const Center(child: Text('ምንም ትዕዛዝ የለም'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: app.orders.length,
      itemBuilder: (context, i) {
        final o = app.orders[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            title: Text('ትዕዛዝ #${o['id']}'),
            subtitle: Text(o['status']?.toString() ?? 'በሂደት ላይ'),
            trailing: Text('${o['total'] ?? 0} ብር'),
          ),
        );
      },
    );
  }
}
