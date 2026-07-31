import 'package:flutter/material.dart';

/// Renders the icons8 coin icon asset. Replaces the 🪙 emoji everywhere in
/// the app — some phones' system emoji font doesn't include 🪙 (Unicode 13,
/// 2020) and shows a "tofu" box instead, which is exactly the "coin emoji
/// doesn't work on some phones" bug that was reported.
class CoinIcon extends StatelessWidget {
  final double size;
  const CoinIcon({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/icons/coin.png', width: size, height: size);
  }
}
