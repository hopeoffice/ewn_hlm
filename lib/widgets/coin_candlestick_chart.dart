import 'package:flutter/material.dart';
import '../services/wallet_service.dart';
import '../theme/app_theme.dart';

/// One synthetic candle body.
class _Candle {
  final double open, close, high, low;
  const _Candle({required this.open, required this.close, required this.high, required this.low});
}

/// Deterministic PRNG — ported 1:1 from _walletMulberry32() in
/// main-coins.js so the same (price, seedKey) pair always produces the
/// same candle layout instead of re-shuffling on every rebuild.
class _Mulberry32 {
  int _seed;
  _Mulberry32(int seed) : _seed = seed;

  double next() {
    _seed = (_seed + 0x6D2B79F5) & 0xFFFFFFFF;
    final seed = _seed;
    var t = _imul(seed ^ (seed >>> 15), seed | 1) & 0xFFFFFFFF;
    t = ((t + _imul(t ^ (t >>> 7), t | 61)) ^ t) & 0xFFFFFFFF;
    return ((t ^ (t >>> 14)) & 0xFFFFFFFF) / 4294967296.0;
  }

  static int _imul(int a, int b) => (a * b) & 0xFFFFFFFF;
}

/// Result of [generateCoinCandles] — candle series plus the y-axis range
/// and the first/last synthetic timestamps.
class CandleChartData {
  final List<_Candle> candles;
  final double min, max;
  final int firstTs, lastTs;
  const CandleChartData({required this.candles, required this.min, required this.max, required this.firstTs, required this.lastTs});
}

/// Ported from buildCoinCandlestickChart() in main-coins.js (2026-07-25
/// revision). Generates [WalletService.walletCandleCount] candles as a
/// random walk confined to a -20%/+15% band around [currentPrice], ending
/// exactly on [currentPrice]. Two behaviors matter for correctness:
///  1. The LAST candle is pinned so its body top is exactly
///     [currentPrice] with no wick above it (open clamped ≤ close, high =
///     close) — otherwise a wick could visually "float" past the
///     dashed current-price line.
///  2. The y-scale is symmetric around [currentPrice] (± the band
///     radius), not auto-fit to wherever the random walk actually
///     wandered — so the current-price line always sits at the exact
///     vertical center of the chart, regardless of the random seed.
/// ⚠️ Decorative only — coinRates/history stores a single admin-set
/// rate per entry, not real OHLC data.
CandleChartData generateCoinCandles(double currentPrice, int seedKey) {
  final count = WalletService.walletCandleCount;
  final bandLow = currentPrice * 0.80;
  final bandHigh = currentPrice * 1.15;
  var genMin = bandLow, genMax = bandHigh;
  if (genMin == genMax) {
    genMin -= 0.001;
    genMax += 0.001;
  }
  final genSpan = genMax - genMin;

  final seed = (currentPrice * 100000).floor() + seedKey;
  final rand = _Mulberry32(seed);

  // Random walk. Step/wick sizes deliberately generous (taller-looking
  // candles) so the walk uses more of the -20%/+15% band instead of
  // huddling near the middle.
  final closes = List<double>.filled(count, 0);
  closes[count - 1] = currentPrice;
  var v = bandLow + rand.next() * (bandHigh - bandLow);
  for (var i = 0; i < count - 1; i++) {
    v += (rand.next() - 0.5) * genSpan * 0.16;
    if (v < bandLow) v = bandLow + (bandLow - v);
    if (v > bandHigh) v = bandHigh - (v - bandHigh);
    closes[i] = v.clamp(bandLow, bandHigh);
  }

  final candles = <_Candle>[];
  for (var i = 0; i < count; i++) {
    final close = closes[i];
    var open = i == 0 ? close + (rand.next() - 0.5) * genSpan * 0.05 : closes[i - 1];
    // Last candle = the "current price" candle: clamp its open so it
    // never sits above currentPrice, guaranteeing it's an up/blue candle
    // whose body top IS currentPrice (pinned as `high` below).
    if (i == count - 1 && open > close) open = close;
    final wick = genSpan * 0.05 * rand.next();
    final high = i == count - 1 ? close : (open > close ? open : close) + wick;
    final low = (open < close ? open : close) - wick;
    candles.add(_Candle(
      open: open,
      close: close,
      high: i == count - 1 ? high : high.clamp(-double.infinity, bandHigh),
      low: low.clamp(bandLow, double.infinity),
    ));
  }

  // Symmetric scale around currentPrice — see doc comment above.
  final radius = (currentPrice - bandLow) > (bandHigh - currentPrice) ? (currentPrice - bandLow) : (bandHigh - currentPrice);
  var min = currentPrice - radius;
  var max = currentPrice + radius;
  if (min == max) {
    min -= 0.001;
    max += 0.001;
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  final stepMs = WalletService.walletCandleSpanMs / (count - 1);
  int tsAt(int i) => now - ((count - 1 - i) * stepMs).round();

  return CandleChartData(candles: candles, min: min, max: max, firstTs: tsAt(0), lastTs: tsAt(count - 1));
}

const _kBuyColor = Color(0xFF2F6FED); // up/buy candle
const _kSellColor = Color(0xFFE63946); // down/sell candle

/// Scrollable candlestick chart + fixed (non-scrolling) right-side price
/// axis, matching the two-<svg> layout in buildCoinCandlestickChart():
/// the candles/gridlines/current-price line scroll horizontally, while
/// the price labels + current-price bubble stay pinned. Defaults to
/// scrolled all the way right (most-recent candle), like opening a
/// trading app to "now".
class CoinCandlestickChart extends StatefulWidget {
  final double currentPrice;
  final bool isUp;
  final int seedKey;
  final double height;

  const CoinCandlestickChart({
    super.key,
    required this.currentPrice,
    required this.isUp,
    required this.seedKey,
    this.height = 220,
  });

  @override
  State<CoinCandlestickChart> createState() => _CoinCandlestickChartState();
}

class _CoinCandlestickChartState extends State<CoinCandlestickChart> {
  final _scrollCtrl = ScrollController();
  late CandleChartData _data;

  @override
  void initState() {
    super.initState();
    _data = generateCoinCandles(widget.currentPrice, widget.seedKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = WalletService.walletCandleSlotPx * _data.candles.length;
    final curColor = widget.isUp ? const Color(0xFF146C2E) : const Color(0xFFB3122B);

    return SizedBox(
      height: widget.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRect(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                scrollDirection: Axis.horizontal,
                child: CustomPaint(
                  size: Size(totalWidth, widget.height),
                  painter: _CandlesPainter(data: _data, curColor: curColor),
                ),
              ),
            ),
          ),
          SizedBox(
            width: WalletService.walletAxisPx,
            height: widget.height,
            child: CustomPaint(
              painter: _AxisPainter(
                data: _data,
                currentPrice: widget.currentPrice,
                curColor: curColor,
                textColor: AppTheme.textMuted(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandlesPainter extends CustomPainter {
  final CandleChartData data;
  final Color curColor;
  const _CandlesPainter({required this.data, required this.curColor});

  double _yAt(double val, double h) {
    const padTop = 16.0, padBottom = 16.0;
    return padTop + (1 - (val - data.min) / (data.max - data.min)) * (h - padTop - padBottom);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final slot = WalletService.walletCandleSlotPx;
    final bodyW = (slot * 0.62).clamp(4.0, double.infinity);

    // Grid lines (4 levels + top/bottom = 5 lines)
    final gridPaint = Paint()
      ..color = const Color(0x1F808080)
      ..strokeWidth = 1;
    for (var g = 0; g <= 4; g++) {
      final gv = data.max - (g / 4) * (data.max - data.min);
      final gy = _yAt(gv, size.height);
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    // Dashed current-price line spanning full scroll width.
    final curY = _yAt(data.candles.last.close, size.height);
    final dashPaint = Paint()
      ..color = curColor.withOpacity(0.9)
      ..strokeWidth = 1.4;
    const dashW = 5.0, gapW = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, curY), Offset((x + dashW).clamp(0, size.width), curY), dashPaint);
      x += dashW + gapW;
    }

    // Candles
    for (var i = 0; i < data.candles.length; i++) {
      final c = data.candles[i];
      final cx = slot * (i + 0.5);
      final isBuy = c.close >= c.open;
      final color = isBuy ? _kBuyColor : _kSellColor;
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = 1.4;
      canvas.drawLine(Offset(cx, _yAt(c.high, size.height)), Offset(cx, _yAt(c.low, size.height)), wickPaint);

      final bodyTop = _yAt(c.open > c.close ? c.open : c.close, size.height);
      final bodyBottom = _yAt(c.open < c.close ? c.open : c.close, size.height);
      final bodyH = (bodyBottom - bodyTop).clamp(1.6, double.infinity);
      final rect = Rect.fromLTWH(cx - bodyW / 2, bodyTop, bodyW, bodyH);
      canvas.drawRect(rect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _CandlesPainter oldDelegate) => oldDelegate.data != data;
}

class _AxisPainter extends CustomPainter {
  final CandleChartData data;
  final double currentPrice;
  final Color curColor;
  final Color textColor;
  const _AxisPainter({required this.data, required this.currentPrice, required this.curColor, required this.textColor});

  double _yAt(double val, double h) {
    const padTop = 16.0, padBottom = 16.0;
    return padTop + (1 - (val - data.min) / (data.max - data.min)) * (h - padTop - padBottom);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var g = 0; g <= 4; g++) {
      final gv = data.max - (g / 4) * (data.max - data.min);
      final gy = _yAt(gv, size.height);
      final tp = TextPainter(
        text: TextSpan(text: gv.toStringAsFixed(4), style: TextStyle(fontSize: 9, color: textColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(4, gy - tp.height / 2));
    }

    final curY = _yAt(currentPrice, size.height);
    final label = currentPrice.toStringAsFixed(4);
    final tp = TextPainter(
      text: TextSpan(text: label, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    final bubbleW = (14 + label.length * 6.2).clamp(0, size.width - 2).toDouble();
    final bubbleRect = RRect.fromRectAndRadius(Rect.fromLTWH(1, curY - 9, bubbleW, 18), const Radius.circular(4));
    canvas.drawRRect(bubbleRect, Paint()..color = curColor);
    tp.paint(canvas, Offset(1 + (bubbleW - tp.width) / 2, curY - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _AxisPainter oldDelegate) => true;
}
