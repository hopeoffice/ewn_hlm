import 'dart:async';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/user_model.dart';
import '../models/category.dart';
import '../services/firebase_service.dart';
import '../services/storage_service.dart';
import '../services/push_service.dart';
import '../services/wallet_service.dart';
import '../services/location_service.dart';

/// Equivalent of the plain `state` object + its helper functions
/// (saveCart, saveLikes, saveOrders, loginWithUserData, restoreLoginSession,
/// logout) spread across main-config.js. Using ChangeNotifier + Provider
/// instead of manual DOM re-renders.
class AppState extends ChangeNotifier {
  final _fb = FirebaseService();

  UserModel? user;
  List<Product> products = [];
  List<CartItem> cart = [];
  List<String> likes = [];
  List<Map<String, dynamic>> orders = [];
  // Admin-managed, live from Realtime DB settings/categories — starts with
  // the static fallback so the UI never renders empty, then gets replaced
  // by loadCategories() in bootstrap(). Mirrors CATEGORIES in main-config.js.
  List<AppCategory> categories = kDefaultCategories;
  String activeCategory = 'all';
  String searchQuery = '';
  bool offline = false;
  int coins = 0;
  String? referralCode;
  int referralCount = 0;

  // ---- Location (Task #13 — checkLocationBanner()/requestLocationPermission()
  // in main-actions.js). locationName is what the header shows; null means
  // "still getting it" (getting_location text). showLocationBanner mirrors
  // the "ask once, never again after saved" behavior via a local flag,
  // same as localStorage's ewn_location_saved.
  String? locationName;
  bool _locationSaved = false;
  bool _locationBannerDismissed = false;
  bool get showLocationBanner => isAuthenticated && !_locationSaved && !_locationBannerDismissed;

  // ---- Notifications (Realtime DB — main-render.js initNotificationsListener) ----
  List<Map<String, dynamic>> notifications = [];
  int unreadNotifCount = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _notifSub;

  // ---- Theme (menu-item "ቀለም ገጽታ" toggle in profile) ----
  ThemeMode themeMode = ThemeMode.light;

  // ---- Language (menu-item "ቋንቋ" — am/en, main-config.js i18n) ----
  String lang = 'am';

  StreamSubscription<int>? _coinSub;
  StreamSubscription<int>? _referralSub;
  StreamSubscription<List<Map<String, dynamic>>>? _coinPurchasesSub;
  StreamSubscription<List<Map<String, dynamic>>>? _coinTxSub;
  List<Map<String, dynamic>> _coinPurchases = [];
  List<Map<String, dynamic>> _coinTransactions = [];

  bool get isAuthenticated => user != null;

  // ---------------- Startup ----------------

  /// Called once from main.dart. Mirrors:
  ///  1) restoreLoginSession() — read persisted session (no TTL)
  ///  2) loadProducts() — subscribe to the live Firestore stream, with
  ///     the Hive cache used only if the stream never delivers data.
  Future<void> bootstrap() async {
    cart = StorageService.loadCart();
    likes = StorageService.loadLikes();
    orders = StorageService.loadOrders();

    // Persisted UI prefs (menu-item "ቀለም ገጽታ" / "ቋንቋ" in profile screen).
    final savedTheme = StorageService.getString('ewn_theme');
    themeMode = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
    lang = StorageService.getString('ewn_lang') ?? 'am';

    user = await StorageService.restoreSession();
    if (user != null) {
      _watchCoins(user!.phone);
      PushService.registerForUser(user!.phone);
      _loadReferralInfo(user!.phone);
    }
    _watchNotifications();
    unawaited(loadCategories());

    // Offline-first paint: show last known products immediately, then
    // let the live stream (below) replace it the instant data arrives.
    final cached = StorageService.loadCachedProducts();
    if (cached.isNotEmpty) {
      products = cached;
      notifyListeners();
    }

    _fb.watchProducts().listen((live) {
      offline = false;
      products = live;
      StorageService.cacheProducts(live); // refresh fallback cache
      notifyListeners();
    }, onError: (_) {
      offline = products.isEmpty; // only show "offline" if we truly have nothing
      notifyListeners();
    });

    notifyListeners();
  }

  // ---------------- Auth (custom phone + 4-digit PIN, main-config.js) ----------------

  Future<String?> login(String phone, String pin) async {
    final data = await _fb.fetchUser(phone);
    if (data == null) return 'user_not_found';
    if (data['pin'].toString() != pin) return 'wrong_pin';
    if (data['blocked'] == true) return 'account_blocked';

    user = UserModel(name: data['name'] as String, phone: phone);
    await StorageService.saveSession(user!);

    // Merge remote cart/orders/likes with local (same merge-by-id logic
    // as loginWithUserData() in main-config.js).
    final remoteOrders = (data['orders'] as Map?)?.values.toList() ?? [];
    for (final o in remoteOrders) {
      final map = Map<String, dynamic>.from(o as Map);
      if (!orders.any((x) => x['id'] == map['id'])) orders.add(map);
    }
    await StorageService.saveOrders(orders);

    final deviceId = StorageService.getOrCreateDeviceId();
    try {
      await _fb.linkDeviceToUser(phone, deviceId);
    } catch (_) {
      // Non-fatal — login should still succeed even if this write fails.
    }

    // ---- Location: DB ውስጥ cityName ካለ header ላይ ያሳዩ (Task #13) ----
    final loc = data['location'] as Map?;
    final cityName = loc?['cityName'] as String?;
    if (cityName != null && cityName.isNotEmpty) {
      locationName = cityName;
      _locationSaved = true;
      await StorageService.setString('ewn_location_saved', '1');
      await StorageService.setString('ewn_location_name', cityName);
    } else {
      _locationSaved = StorageService.getString('ewn_location_saved') == '1';
      locationName = StorageService.getString('ewn_location_name');
    }

    _watchCoins(phone);
    PushService.registerForUser(phone); // Step 3 — fire-and-forget
    _loadReferralInfo(phone);
    _watchNotifications();
    notifyListeners();
    return null; // success
  }

  Future<void> _loadReferralInfo(String phone) async {
    referralCode = await _fb.getOrCreateReferralCode(phone);
    _referralSub?.cancel();
    _referralSub = _fb.watchReferralCount(phone).listen((count) {
      referralCount = count;
      notifyListeners();
    });
    notifyListeners();
  }

  void _watchCoins(String phone) {
    _coinSub?.cancel();
    _coinSub = _fb.watchCoinBalance(phone).listen((value) {
      coins = value;
      notifyListeners();
    });
    _coinPurchasesSub?.cancel();
    _coinPurchasesSub = _fb.watchCoinPurchases(phone).listen((list) {
      _coinPurchases = list;
      notifyListeners();
    });
    _coinTxSub?.cancel();
    _coinTxSub = _fb.watchCoinTransactions(phone).listen((list) {
      _coinTransactions = list;
      notifyListeners();
    });
  }

  /// Ported from renderTransactionHistoryScreen()'s feedItems merge/sort:
  /// pending buy-coin requests + confirmed coin transactions, newest first.
  List<CoinFeedItem> get coinFeed {
    final items = <CoinFeedItem>[];
    for (final p in _coinPurchases) {
      if (p['status'] == 'pending') {
        final time = DateTime.tryParse(p['date'] as String? ?? '')?.millisecondsSinceEpoch ?? 0;
        items.add(CoinFeedItem.pending(time: time, coins: (p['coins'] as num?)?.toInt() ?? 0, date: p['date'] as String?));
      }
    }
    for (final tx in _coinTransactions) {
      items.add(CoinFeedItem.tx(
        time: (tx['timestamp'] as num?)?.toInt() ?? 0,
        type: tx['type'] as String? ?? '',
        amount: (tx['amount'] as num?)?.toInt() ?? 0,
        orderId: tx['orderId'] as String?,
        orderPercent: (tx['orderPercent'] as num?)?.toInt(),
      ));
    }
    items.sort((a, b) => b.time.compareTo(a.time));
    return items;
  }

  /// Ported from submitBuyCoins() in main-coins.js.
  Future<bool> submitBuyCoins({
    required String name,
    required double amountETB,
    required String paymentMethodLabel,
    required List<int> receiptBytes,
    required String receiptFilename,
  }) {
    if (!isAuthenticated) return Future.value(false);
    return _fb.submitBuyCoins(
      phone: user!.phone,
      name: name,
      amountETB: amountETB,
      coins: WalletService.etbToCoins(amountETB),
      paymentMethodLabel: paymentMethodLabel,
      receiptBytes: receiptBytes,
      receiptFilename: receiptFilename,
    );
  }

  // ---------------- Location (Task #13) ----------------

  /// User tapped "ፍቀድ" (Allow) on the banner. Mirrors
  /// requestLocationPermission() in main-actions.js: get GPS position,
  /// reverse-geocode to a city name, save to Realtime DB, update the
  /// header. Silently does nothing on failure/denial — the banner simply
  /// stays visible so they can try again, same as the web app.
  Future<void> requestLocation() async {
    if (!isAuthenticated) return;
    final result = await LocationService.fetchLocation(lang: lang);
    if (result == null) return;

    locationName = result.cityName;
    _locationSaved = true;
    notifyListeners();

    await StorageService.setString('ewn_location_saved', '1');
    await StorageService.setString('ewn_location_name', result.cityName);
    try {
      await _fb.saveLocation(user!.phone, result.toMap());
    } catch (_) {
      // Non-fatal — same as the web app's try/catch around the RTDB write.
    }
  }

  /// User tapped "ቆየት" (Later) — hide for this session only, same as
  /// dismissLocationBanner() in main-actions.js (asks again next visit).
  void dismissLocationBanner() {
    _locationBannerDismissed = true;
    notifyListeners();
  }

  /// Step 1 of the auth flow — mirrors submitAuthPhone() in main-config.js:
  /// look up users/{phone} to decide whether to show the login (PIN) step
  /// or the registration step next. Returns the raw user data map if the
  /// phone is already registered, or null if it's a new number.
  Future<Map<String, dynamic>?> checkPhone(String phone) => _fb.fetchUser(phone);

  /// Ported from loadPaymentAccountsFromDb() in main-actions.js.
  Future<Map<String, String>?> fetchPaymentAccounts() => _fb.fetchPaymentAccounts();

  static final RegExp ethioPhoneRe = RegExp(r'^(09|07)\d{8}$');

  /// [incomingReferralCode] = the code the new user typed in (someone
  /// else's share link) — optional, mirrors `auth-reg-ref` field / the
  /// `?ref=` query param handling in index.html.
  /// [securityQuestion]/[securityAnswer] power the "ፓስዎርድ ረሳሁ?" flow —
  /// required at registration, same as the web's auth-reg-question /
  /// auth-reg-answer fields.
  Future<String?> register(
    String name,
    String phone,
    String pin, {
    required String securityQuestion,
    required String securityAnswer,
    String? incomingReferralCode,
  }) async {
    final existing = await _fb.fetchUser(phone);
    if (existing != null) return 'already_registered';

    final myCode = FirebaseService.generateReferralCode();

    await _fb.createUser(phone, {
      'name': name,
      'pin': pin,
      'securityQuestion': securityQuestion,
      'securityAnswer': securityAnswer.toLowerCase(),
      'cart': [],
      'likes': [],
      'orders': {},
      'referralCode': myCode, // saved at registration time, same as promoCode in main-config.js
    });
    await _fb.setReferralIndex(myCode, phone);
    await _fb.awardSignupBonus(phone);

    // Credit whoever referred this new user, if a valid code was given.
    final incoming = incomingReferralCode?.trim().toUpperCase();
    if (incoming != null && incoming.length >= 6 && incoming != myCode) {
      final ownerPhone = await _fb.resolveReferralOwner(incoming);
      if (ownerPhone != null) {
        await _fb.trackReferralUse(incoming, phone);
        final newCount = await _fb.incrementReferralCount(ownerPhone);
        final withinCap = newCount == null || newCount <= WalletService.maxReferralCountForCoins;
        if (withinCap) {
          await _fb.awardReferralCoins(incoming, ownerPhone, phone);
        }
      }
    }

    return login(phone, pin);
  }

  /// The "ፓስዎርድ ረሳሁ?" flow — mirrors submitForgotPin() in main-config.js.
  /// Returns null on success (PIN has been changed server-side), or an
  /// error code: 'wrong_answer', 'invalid_pin', 'locked_try_later',
  /// 'user_not_found', or 'reset_failed'.
  Future<String?> resetPin(String phone, String securityAnswer, String newPin) async {
    final result = await _fb.resetPin(phone: phone, securityAnswer: securityAnswer, newPin: newPin);
    return result.ok ? null : (result.error ?? 'reset_failed');
  }

  Future<void> logout() async {
    user = null;
    cart = [];
    orders = [];
    coins = 0;
    referralCode = null;
    referralCount = 0;
    locationName = null;
    _locationSaved = false;
    _locationBannerDismissed = false;
    _coinSub?.cancel();
    _referralSub?.cancel();
    _coinPurchasesSub?.cancel();
    _coinTxSub?.cancel();
    _coinPurchases = [];
    _coinTransactions = [];
    await StorageService.saveCart(cart);
    await StorageService.saveOrders(orders);
    await StorageService.setString('ewn_location_saved', '0');
    _watchNotifications(); // drop the personal branch, keep global broadcasts
    notifyListeners();
  }

  // ---------------- Notifications (main-render.js initNotificationsListener/renderNotifications) ----------------

  void _watchNotifications() {
    _notifSub?.cancel();
    _notifSub = _fb.watchNotifications(phone: user?.phone).listen((list) {
      notifications = list;
      final lastSeen = int.tryParse(StorageService.getString('ewn_notif_last_seen') ?? '0') ?? 0;
      unreadNotifCount = notifications.where((n) {
        final ts = (n['timestamp'] as num?)?.toInt() ??
            DateTime.tryParse(n['date']?.toString() ?? '')?.millisecondsSinceEpoch ??
            0;
        return ts > lastSeen;
      }).length;
      notifyListeners();
    });
  }

  /// Called when the notifications screen is opened — resets the badge,
  /// same as renderNotifications() setting ewn_notif_last_seen.
  Future<void> markNotificationsSeen() async {
    unreadNotifCount = 0;
    await StorageService.setString('ewn_notif_last_seen', DateTime.now().millisecondsSinceEpoch.toString());
    notifyListeners();
  }

  // ---------------- Theme (profile "ቀለም ገጽታ" toggle) ----------------

  Future<void> toggleTheme() async {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await StorageService.setString('ewn_theme', themeMode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  // ---------------- Language (profile "ቋንቋ" toggle — am/en) ----------------

  Future<void> setLanguage(String code) async {
    lang = code;
    await StorageService.setString('ewn_lang', code);
    notifyListeners();
  }

  // ---------------- Cart (main-actions.js addToCart / main-config.js saveCart) ----------------

  void addToCart(Product p, {String? color, int qty = 1}) {
    if (p.outOfStock) return;
    final idx = cart.indexWhere((c) => c.id == p.id && c.color == color);
    if (idx != -1) {
      cart[idx].qty += qty;
    } else {
      cart.add(CartItem(
        id: p.id,
        color: color,
        qty: qty,
        price: p.displayPrice,
        name: p.displayName(lang),
        image: p.thumbnail,
      ));
    }
    _persistCart();
  }

  /// Ported from setCartQtyForBuyNow() in main-actions.js. Unlike
  /// addToCart(), this SETS the line's quantity rather than incrementing
  /// it — used only by the product sheet's "Buy Now" button, so tapping
  /// Buy Now with qty=1 always results in exactly 1 in the cart for that
  /// line, regardless of what was already there.
  void setCartQty(Product p, {String? color, int qty = 1}) {
    if (p.outOfStock) return;
    final idx = cart.indexWhere((c) => c.id == p.id && c.color == color);
    if (idx != -1) {
      cart[idx].qty = qty;
    } else {
      cart.add(CartItem(
        id: p.id,
        color: color,
        qty: qty,
        price: p.displayPrice,
        name: p.displayName(lang),
        image: p.thumbnail,
      ));
    }
    _persistCart();
  }

  void removeFromCart(String id, String? color) {
    cart.removeWhere((c) => c.id == id && c.color == color);
    _persistCart();
  }

  void updateQty(String id, String? color, int qty) {
    final idx = cart.indexWhere((c) => c.id == id && c.color == color);
    if (idx == -1) return;
    if (qty <= 0) {
      cart.removeAt(idx);
    } else {
      cart[idx].qty = qty;
    }
    _persistCart();
  }

  void _persistCart() {
    StorageService.saveCart(cart);
    if (isAuthenticated) _fb.syncCartDebounced(user!.phone, cart);
    notifyListeners();
  }

  double get cartTotal => cart.fold(0, (sum, c) => sum + c.lineTotal);
  int get cartCount => cart.fold(0, (sum, c) => sum + c.qty);

  // ---------------- Checkout (main-actions.js placeOrder + main-render.js Telegram senders) ----------------

  /// [cartIndex] null = whole cart, otherwise a single line (mirrors the
  /// `singleCartItemId` param in the JS placeOrder()).
  /// [receiptBytes]/[receiptFilename] = screenshot of the bank/Telebirr
  /// transfer; pass null when the order is 100% covered by coins.
  /// Returns null on success, or an error code string.
  Future<String?> placeOrder({
    int? cartIndex,
    List<int>? receiptBytes,
    String? receiptFilename,
    String paymentMethod = 'telebirr',
    String? paymentMethodLabel,
    required String customerName,
    required String address,
    required String region,
    int coinsUsed = 0,
    String? coinPin,
  }) async {
    if (!isAuthenticated) return 'not_authenticated';

    // 🚫 Blocked-account guard — re-read live, same as submitCheckout()'s
    // fresh users/{phone}/blocked check (don't trust a possibly-stale
    // in-memory session).
    final blocked = await _fb.fetchUser(user!.phone).then((d) => d?['blocked'] == true);
    if (blocked) return 'account_blocked';

    final itemsToOrder = cartIndex != null ? [cart[cartIndex]] : List<CartItem>.from(cart);
    if (itemsToOrder.isEmpty) return 'empty_cart';

    final rawTotal = itemsToOrder.fold<double>(0, (s, i) => s + i.lineTotal);
    final discountETB = coinsUsed > 0 ? WalletService.coinsToEtb(coinsUsed) : 0.0;
    final total = coinsUsed > 0 ? WalletService.applyCoinWaiver(rawTotal, discountETB) : rawTotal;
    final coinPercent =
        (coinsUsed > 0 && rawTotal > 0) ? (discountETB / rawTotal * 100).round().clamp(0, 100) : 0;

    // 🪙 A receipt proves a Telebirr/bank transfer — not needed when coins
    // fully cover the order.
    if (total > 0 && (receiptBytes == null || receiptFilename == null)) {
      return 'receipt_required';
    }

    String methodLabel = paymentMethodLabel ?? paymentMethod;
    if (coinPercent >= 100) {
      methodLabel = lang == 'am' ? '🪙 100% Coins ተከፍሏል' : '🪙 100% Paid with Coins';
    } else if (coinPercent > 0) {
      methodLabel = '🪙 $coinPercent% Coins + $methodLabel';
    }

    final order = {
      'id': 'ORD-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}',
      'items': itemsToOrder.map((i) => i.toMap()).toList(),
      'total': total,
      'subtotal': rawTotal,
      'coinsUsed': coinsUsed,
      'coinDiscount': discountETB,
      'coinPercent': coinPercent,
      'status': 'pending',
      'date': DateTime.now().toIso8601String(),
      'paymentMethod': methodLabel,
      'customer': {'name': customerName, 'phone': user!.phone, 'location': address, 'region': region},
    };

    orders.add(order);
    await StorageService.saveOrders(orders);
    await _fb.saveOrder(user!.phone, order);

    // Remove ordered items from the cart.
    if (cartIndex != null) {
      cart.removeAt(cartIndex);
    } else {
      cart.clear();
    }
    _persistCart();

    // Notify Telegram — photo+caption if a receipt was attached (bank/
    // Telebirr transfer), otherwise a text-only notice (coin-only order).
    final caption = _buildTelegramOrderText(order);
    bool sent;
    if (receiptBytes != null && receiptFilename != null) {
      sent = await _fb.sendReceiptToTelegram(
        caption: caption,
        receiptBytes: receiptBytes,
        filename: receiptFilename,
      );
    } else {
      sent = await _fb.sendOrderNotificationToTelegram(caption);
    }
    if (!sent) debugPrint('Telegram order notification failed for ${order['id']}');

    // 🪙 Deduct coins + record usage only AFTER the order succeeded —
    // mirrors finalizeCoinRedemption() being called at the very end of
    // submitCheckout(). If this fails, the order still stands (matches
    // the web app's behavior); we just log it rather than blocking.
    if (coinsUsed > 0 && coinPin != null) {
      final redeemErr = await redeemCoinsForOrder(
        coinsToUse: coinsUsed,
        cartTotal: rawTotal,
        pin: coinPin,
        orderId: order['id'] as String,
        orderPercent: coinPercent,
      );
      if (redeemErr != null) debugPrint('Coin redemption failed for ${order['id']}: $redeemErr');
    }

    notifyListeners();
    return null;
  }

  // ---------------- Coin redemption at checkout (main-coins.js) ----------------
  // NOTE: coins are NEVER redeemed from the wallet screen on their own —
  // only as a discount applied while placing an order, and only after the
  // account PIN is re-entered (checked server-side by the Worker). The
  // wallet screen's old standalone "Redeem" button was wrong and is being
  // replaced with the real "🪙 coin ተጠቀም" checkout toggle when we get to
  // checkout_screen.dart / wallet_screen.dart in the file plan.

  /// Mirrors getCoinRedemptionEligibility() in main-coins.js. Call this
  /// with the current cart/order total to decide whether to show the
  /// "🪙 Use Coins" toggle at all, and how many coins it can offer.
  CoinRedemptionEligibility coinRedemptionEligibility(double cartTotal) {
    if (!isAuthenticated) {
      return const CoinRedemptionEligibility(eligible: false, maxUsableCoins: 0, reason: 'no_user');
    }
    if (coins <= 0) {
      return const CoinRedemptionEligibility(eligible: false, maxUsableCoins: 0, reason: 'no_coins');
    }
    if (WalletService.coinsToEtb(coins) <= WalletService.minRedeemEtb) {
      return const CoinRedemptionEligibility(eligible: false, maxUsableCoins: 0, reason: 'balance_too_low');
    }
    final maxCoinsByOrder = WalletService.etbToCoins(cartTotal);
    final maxUsableCoins = coins < maxCoinsByOrder ? coins : maxCoinsByOrder;
    return CoinRedemptionEligibility(
      eligible: maxUsableCoins > 0,
      maxUsableCoins: maxUsableCoins,
      reason: 'ok',
    );
  }

  /// Actually spends [coinsToUse] as a discount on an order worth
  /// [cartTotal], re-checking [pin] server-side. Returns null + updates
  /// [coins] on success, or an error code string on failure — one of
  /// 'not_authenticated', 'wrong_pin', 'locked_try_later', 'out_of_range',
  /// 'exceeds_max_usable', or 'redeem_failed'.
  Future<String?> redeemCoinsForOrder({
    required int coinsToUse,
    required double cartTotal,
    required String pin,
    String? orderId,
    int? orderPercent,
  }) async {
    if (!isAuthenticated) return 'not_authenticated';
    final result = await _fb.redeemCoins(
      phone: user!.phone,
      pin: pin,
      coinsToUse: coinsToUse,
      cartTotal: cartTotal,
      orderId: orderId,
      orderPercent: orderPercent,
    );
    if (!result.ok) return result.error ?? 'redeem_failed';
    if (result.coins != null) coins = result.coins!;
    notifyListeners();
    return null;
  }

  /// Ported from buildTelegramOrderText() in main-render.js.
  String _buildTelegramOrderText(Map<String, dynamic> order) {
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    final itemsText = items.map((i) => '${i['name']} x${i['qty']}').join(', ');
    return [
      '🛍️ አዲስ ትዕዛዝ / New Order',
      '🆔 ${order['id']}',
      '👤 ${(order['customer'] as Map)['name']} — ${(order['customer'] as Map)['phone']}',
      '📦 $itemsText',
      '💰 ጠቅላላ / Total: ${order['total']} ETB',
      '⏰ ${order['date']}',
    ].join('\n');
  }

  // ---------------- Likes ----------------

  void toggleLike(String productId) {
    if (likes.contains(productId)) {
      likes.remove(productId);
    } else {
      likes.add(productId);
    }
    StorageService.saveLikes(likes);
    if (isAuthenticated) _fb.syncLikes(user!.phone, likes);
    notifyListeners();
  }

  // ---------------- Category / search filter ----------------

  /// Mirrors loadCategoriesFromFirebase() + _applyCachedCategoriesIfAny()
  /// in main-config.js: try the live admin list first, fall back to the
  /// last-known cached copy, and only fall back to the static defaults if
  /// neither is available. "all" is always pinned first.
  Future<void> loadCategories() async {
    final live = await _fb.fetchCategories();
    if (live != null && live.isNotEmpty) {
      categories = [kAllCategory, ...live];
      await StorageService.cacheCategories(categories);
    } else {
      final cached = StorageService.loadCachedCategories();
      if (cached != null) categories = cached;
      // else: keep whatever is already in `categories` (static defaults).
    }
    notifyListeners();
  }

  List<Product> get filteredProducts {
    return products.where((p) {
      if (p.hidden) return false;
      final matchesCategory = activeCategory == 'all' || p.category == activeCategory;
      final matchesSearch = searchQuery.isEmpty ||
          p.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (p.nameAm?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
      return matchesCategory && matchesSearch;
    }).toList();
  }

  /// Mirrors the #discount-section in index.html — only products with a
  /// real discountedPrice < price, shown ahead of the main grid.
  List<Product> get discountedProducts {
    return products
        .where((p) => !p.hidden && p.discountedPrice != null && p.discountedPrice! < p.price)
        .toList();
  }

  void setCategory(String cat) {
    activeCategory = cat;
    notifyListeners();
  }

  void setSearch(String q) {
    searchQuery = q;
    notifyListeners();
  }

  @override
  void dispose() {
    _coinSub?.cancel();
    _referralSub?.cancel();
    _notifSub?.cancel();
    _coinPurchasesSub?.cancel();
    _coinTxSub?.cancel();
    super.dispose();
  }
}

/// Ported from the merged feedItems row types in renderTransactionHistoryScreen()
/// (main-coins.js): either a still-pending "Buy Coins" request, or a
/// confirmed ledger entry (earn/redeem/admin adjustment).
class CoinFeedItem {
  final int time;
  final bool isPending;
  final int coins; // pending only — the amount requested
  final String? date; // pending only

  final String type; // tx only
  final int amount; // tx only — signed (+credit / -debit)
  final String? orderId; // tx only, redeem rows
  final int? orderPercent; // tx only, redeem rows

  CoinFeedItem.pending({required this.time, required this.coins, this.date})
      : isPending = true,
        type = '',
        amount = 0,
        orderId = null,
        orderPercent = null;

  CoinFeedItem.tx({required this.time, required this.type, required this.amount, this.orderId, this.orderPercent})
      : isPending = false,
        coins = 0,
        date = null;
}
