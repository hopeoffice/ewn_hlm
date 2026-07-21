/// Ported verbatim from the "COIN CONSTANTS" block in main-coins.js.
/// Keep these numbers in sync with the Cloudflare Worker, which remains
/// the source of truth / enforcement point (client-side is UX only).
class WalletService {
  static const double coinValueEtb = 0.068; // 1 Coin = 0.068 ብር
  static const int signupBonusCoins = 100;
  static const int referralCoins = 147;
  static const int maxReferralCountForCoins = 30;
  static const double minBuyCoinsEtb = 1500;
  static const int minRedeemCoins = 22050;

  static double get minRedeemEtb =>
      double.parse((minRedeemCoins * coinValueEtb).toStringAsFixed(2));

  static double coinsToEtb(int coins) =>
      double.parse((coins * coinValueEtb).toStringAsFixed(2));

  static int etbToCoins(double etb) => (etb / coinValueEtb).floor();
}
