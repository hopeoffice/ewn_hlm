import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/user_model.dart';
import '../models/category.dart';
import '../services/firebase_service.dart';
import '../services/storage_service.dart';
import '../services/push_service.dart';
import '../services/wallet_service.dart';

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
  String activeCategory = 'all';
  String searchQuery = '';
  bool offline = false;
  int coins = 0;
  String? referralCode;
  int referralCount = 0;

  StreamSubscription<int>? _coinSub;
  StreamSubscription<int>? _referralSub;

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

    user = await StorageService.restoreSession();
    if (user != null) {
      _watchCoins(user!.phone);
      PushService.registerForUser(user!.phone);
      _loadReferralInfo(user!.phone);
    }

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

    _watchCoins(phone);
    PushService.registerForUser(phone); // Step 3 — fire-and-forget
    _loadReferralInfo(phone);
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
  }

  /// [incomingReferralCode] = the code the new user typed in (someone
  /// else's share link) — optional, mirrors `auth-reg-ref` field / the
  /// `?ref=` query param handling in index.html.
  Future<String?> register(String name, String phone, String pin, {String? incomingReferralCode}) async {
    final existing = await _fb.fetchUser(phone);
    if (existing != null) return 'already_registered';

    final myCode = FirebaseService.generateReferralCode();

    await _fb.createUser(phone, {
      'name': name,
      'pin': pin,
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

  Future<void> logout() async {
    user = null;
    cart = [];
    orders = [];
    coins = 0;
    referralCode = null;
    referralCount = 0;
    _coinSub?.cancel();
    _referralSub?.cancel();
    await StorageService.clearSession();
    await StorageService.saveCart(cart);
    await StorageService.saveOrders(orders);
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
        name: p.name,
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
  }) async {
    if (!isAuthenticated) return 'not_authenticated';

    final itemsToOrder = cartIndex != null ? [cart[cartIndex]] : List<CartItem>.from(cart);
    if (itemsToOrder.isEmpty) return 'empty_cart';

    final order = {
      'id': 'ORD-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}',
      'items': itemsToOrder.map((i) => i.toMap()).toList(),
      'total': itemsToOrder.fold<double>(0, (s, i) => s + i.lineTotal),
      'status': 'pending',
      'date': DateTime.now().toIso8601String(),
      'paymentMethod': paymentMethod,
      'customer': {'name': user!.name, 'phone': user!.phone},
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

    notifyListeners();
    return null;
  }

  /// Ported from the redeemCoins Worker call in main-coins.js. The
  /// client only checks MIN_REDEEM_COINS for UX; the Worker re-checks
  /// the real balance server-side before paying out (same as the PWA).
  Future<String?> redeemCoins() async {
    if (!isAuthenticated) return 'not_authenticated';
    final ok = await _fb.redeemCoins(user!.phone, coins);
    return ok ? null : 'redeem_failed';
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

  // Fallback categories (same as CATEGORIES in main-config.js). TODO:
  // wire up loadCategoriesFromFirebase() equivalent once the admin
  // panel's `settings/categories` doc is ported.
  List<AppCategory> get categories => kDefaultCategories;

  List<Product> get filteredProducts {
    return products.where((p) {
      if (p.hidden) return false;
      final matchesCategory = activeCategory == 'all' || p.category == activeCategory;
      final matchesSearch = searchQuery.isEmpty ||
          p.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
          p.nameEn.toLowerCase().contains(searchQuery.toLowerCase());
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
    super.dispose();
  }
}
