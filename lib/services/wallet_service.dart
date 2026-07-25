/// Ported verbatim from the "COIN CONSTANTS" block + redemption math in
/// main-coins.js. Keep these numbers in sync with the Cloudflare Worker,
/// which remains the source of truth / enforcement point (client-side is
/// UX only — every number here is re-validated server-side).
class WalletService {
  static const double coinValueEtb = 0.068; // 1 Coin = 0.068 ብር
  static const int signupBonusCoins = 100;
  static const int referralCoins = 147;
  static const int maxReferralCountForCoins = 30;
  static const double minBuyCoinsEtb = 1500; // minimum "Buy Coins" purchase
  static const int minRedeemCoins = 22050; // balance-value gate, not order size

  // ---- Wallet screen (💱) — ported from the MIN_SELL_COINS/MIN_TRANSFER_
  // COINS/WALLET_* constants block in main-coins.js. ----
  static const int minSellCoins = 5000;
  static const int minTransferCoins = 5000;
  static const int walletHistoryLimit = 30;
  static const int walletCandleCount = 90; // total synthetic candles generated
  static const int walletVisibleCandles = 10; // visible at once (rest via horizontal scroll)
  static const double walletCandleSlotPx = 32; // px width per candle slot
  static const double walletAxisPx = 56; // fixed (non-scrolling) price-axis width
  static const int walletCandleSpanMs = 3 * 24 * 60 * 60 * 1000; // 3 days of fake history

  // ---- Edit Profile (👤) — ported from NAME_CHANGE_COOLDOWN_MS in
  // main-coins.js (30-day name-change cooldown, enforced server-side too). ----
  static const int nameChangeCooldownMs = 30 * 24 * 60 * 60 * 1000;

  // ---- Privacy Policy — canonical hosted page (EWN_BASE_URL in index.html). ----
  static const String privacyPolicyUrl = 'https://ewn-hlm.web.app/privacy.html';

  static double get minRedeemEtb =>
      double.parse((minRedeemCoins * coinValueEtb).toStringAsFixed(2));

  static double coinsToEtb(int coins) =>
      double.parse((coins * coinValueEtb).toStringAsFixed(2));

  static int etbToCoins(double etb) => (etb / coinValueEtb).floor();

  /// Ported from applyCoinWaiver() in main-coins.js. Because coins are
  /// whole numbers, a coin-based discount can fall up to just under one
  /// coin's value (0.068 ETB) short of the order total. Rather than
  /// asking the Worker to redeem more coins than the order is worth
  /// (which it correctly rejects), that sliver is waived — the customer
  /// pays 0 instead of a stray few cents.
  static double applyCoinWaiver(double rawTotal, double discountETB) {
    final remainder = rawTotal - discountETB;
    if (discountETB > 0 && remainder > 0 && remainder < coinValueEtb) return 0;
    return remainder < 0 ? 0 : remainder;
  }
}

/// Ported from getCoinRedemptionEligibility() in main-coins.js.
/// [reason] is one of: 'no_user', 'no_coins', 'balance_too_low', 'ok'.
class CoinRedemptionEligibility {
  final bool eligible;
  final int maxUsableCoins;
  final String reason;

  const CoinRedemptionEligibility({
    required this.eligible,
    required this.maxUsableCoins,
    required this.reason,
  });
}
