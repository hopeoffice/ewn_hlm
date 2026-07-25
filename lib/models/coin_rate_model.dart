/// One admin-set buy/sell rate — either the current live rate
/// (`coinRates/current`) or one entry of the history log
/// (`coinRates/history/{ts}`). Ported from the shape written by the admin
/// panel in admin.html.
class CoinRateSnapshot {
  final double buyRate;
  final double sellRate;
  final int updatedAt;

  const CoinRateSnapshot({required this.buyRate, required this.sellRate, required this.updatedAt});
}

/// A single history entry, keyed by its timestamp (the RTDB key itself).
class CoinRatePoint {
  final int ts;
  final double buyRate;
  final double sellRate;

  const CoinRatePoint({required this.ts, required this.buyRate, required this.sellRate});
}

/// Return value of FirebaseService.fetchCoinRateData() — ported from the
/// `{ current, history }` object returned by fetchCoinRateData() in
/// main-coins.js.
class CoinRateData {
  final CoinRateSnapshot current;
  final List<CoinRatePoint> history;

  const CoinRateData({required this.current, required this.history});
}
