import 'dart:async';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/user_model.dart';
import '../models/category.dart';
import '../models/coin_rate_model.dart';
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
  StreamSubscription<List<Map<String, dynamic>>>? _ordersSub;

  // ---- Theme (menu-item "ቀለም ገጽታ" toggle in profile) ----
  ThemeMode themeMode = ThemeMode.light;

  // ---- Language (menu-item "ቋንቋ" — am/en, main-config.js i18n) ----
  String lang = 'am';

  StreamSubscription<int>? _coinSub;
  StreamSubscription<int>? _referralSub;
  StreamSubscription<List<Map<String, dynamic>>>? _coinPurchasesSub;
  StreamSubscription<List<Map<String, dynamic>>>? _coinSellRequestsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _coinTxSub;
  List<Map<String, dynamic>> _coinPurchases = [];
  List<Map<String, dynamic>> _coinSellRequests = [];
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
    // Seed from whatever was last cached locally so the header doesn't
    // flash "getting location" on cold start; _syncFromRemoteOnRestore
    // below refreshes this from Firebase right after, for both logged-in
    // and guest sessions.
    _locationSaved = StorageService.getString('ewn_location_saved') == '1';
    locationName = StorageService.getString('ewn_location_name');
    if (user != null) {
      _watchCoins(user!.phone);
      _watchOrders(user!.phone);
      PushService.registerForUser(user!.phone);
      _loadReferralInfo(user!.phone);
      // BUGFIX: a session restored from the cached login (no server
      // round-trip) used to skip Firebase entirely — cart/likes stayed
      // whatever was last cached on *this* device, and location fell
      // back to the local cache instead of ever checking Firebase again.
      // Pull the account's Firebase record once on startup and merge it
      // in, same as a fresh interactive login does.
      unawaited(_syncFromRemoteOnRestore(user!.phone));
    }
    notifications = StorageService.loadNotifications();
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

  // ---------------- Auth (phone + email/password, Worker-verified) ----------------

  /// Ported from submitAuthLogin() in main-config.js — POST /login via
  /// the Worker (password hash comparison + lockout are all server-side
  /// now; the client never sees or compares a password hash).
  ///
  /// Returns null on success, or an error code: 'wrong_password',
  /// 'account_blocked', 'locked_try_later', 'user_not_found', or the
  /// special 'migration_required' — the caller (auth_sheet.dart) should
  /// treat that one as a silent redirect to the migrate step, not an
  /// error message, exactly like goToAuthStep('auth-step-migrate') does
  /// in the web app.
  Future<String?> login(String phone, String password) async {
    final result = await _fb.loginWithPassword(phone: phone, password: password);
    if (!result.ok) return result.error ?? 'connection_error';
    await _completeLogin(phone, result.userData!);
    return null;
  }

  /// Shared session-setup — was inlined in login() alone before; now also
  /// used by completeRegister()/completeMigrate()/completeForgotPassword()
  /// since all four now end with the same Worker-returned `userData`
  /// getting logged straight in (matching loginWithUserData() in
  /// main-config.js, which every one of those flows calls at the end).
  Future<void> _completeLogin(String phone, Map<String, dynamic> data) async {
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

    // BUGFIX: cart and likes were pushed TO Firebase (syncCartDebounced /
    // syncLikes) but never pulled back down on login, so logging in on a
    // new device/browser silently lost whatever cart/likes were already
    // saved under this account. Merge them in the same way orders are
    // merged above, so nothing from either side is dropped.
    _mergeRemoteCart(data['cart']);
    _mergeRemoteLikes(data['likes']);
    await StorageService.saveCart(cart);
    await StorageService.saveLikes(likes);
    // Push the merged result back so both sides agree afterward.
    _fb.syncCartDebounced(phone, cart);
    _fb.syncLikes(phone, likes);

    final deviceId = StorageService.getOrCreateDeviceId();
    try {
      await _fb.linkDeviceToUser(phone, deviceId);
    } catch (_) {
      // Non-fatal — login should still succeed even if this write fails.
    }

    _applyRemoteLocation(data['location'] as Map?);

    _watchCoins(phone);
    _watchOrders(phone);
    PushService.registerForUser(phone); // Step 3 — fire-and-forget
    _loadReferralInfo(phone);
    _watchNotifications();
    notifyListeners();
  }

  /// Adds remote cart lines (users/{phone}/cart) that aren't already
  /// present locally (matched by product id + color), and bumps the
  /// local quantity up to the remote one when a line exists on both
  /// sides but the remote qty is higher — mirrors the additive spirit of
  /// the orders merge just above, applied to cart lines.
  void _mergeRemoteCart(dynamic raw) {
    if (raw is! List) return;
    for (final entry in raw) {
      if (entry is! Map) continue;
      final remote = CartItem.fromMap(Map<String, dynamic>.from(entry));
      final idx = cart.indexWhere((c) => c.id == remote.id && c.color == remote.color);
      if (idx == -1) {
        cart.add(remote);
      } else if (remote.qty > cart[idx].qty) {
        cart[idx].qty = remote.qty;
      }
    }
  }

  /// Unions remote likes (users/{phone}/likes) into the local list.
  void _mergeRemoteLikes(dynamic raw) {
    if (raw is! List) return;
    for (final id in raw) {
      final s = id?.toString();
      if (s != null && s.isNotEmpty && !likes.contains(s)) likes.add(s);
    }
  }

  /// Ported from the "DB ውስጥ cityName ካለ header ላይ ያሳዩ" behaviour
  /// (Task #13): if the account already has a saved location in
  /// Firebase, show it and never re-ask — only fall back to whatever was
  /// last cached on this device if Firebase has nothing.
  void _applyRemoteLocation(Map? loc) {
    final cityName = loc?['cityName'] as String?;
    if (cityName != null && cityName.isNotEmpty) {
      locationName = cityName;
      _locationSaved = true;
      StorageService.setString('ewn_location_saved', '1');
      StorageService.setString('ewn_location_name', cityName);
    } else {
      _locationSaved = StorageService.getString('ewn_location_saved') == '1';
      locationName = StorageService.getString('ewn_location_name');
    }
  }

  /// Fire-and-forget: fetches the account's Firebase record on a silent
  /// session restore (app cold start with an already-logged-in session)
  /// and merges in cart/likes/location, then notifies listeners so the
  /// UI picks up anything that changed on another device. Non-fatal if
  /// this fails (offline, etc.) — the locally-cached values already
  /// loaded in bootstrap() stand in the meantime.
  Future<void> _syncFromRemoteOnRestore(String phone) async {
    try {
      final data = await _fb.fetchUser(phone);
      if (data == null) return;
      _mergeRemoteCart(data['cart']);
      _mergeRemoteLikes(data['likes']);
      await StorageService.saveCart(cart);
      await StorageService.saveLikes(likes);
      _applyRemoteLocation(data['location'] as Map?);
      notifyListeners();
    } catch (_) {
      // Offline or transient — keep the locally-cached values as-is.
    }
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
    _coinSellRequestsSub?.cancel();
    _coinSellRequestsSub = _fb.watchCoinSellRequests(phone).listen((list) {
      _coinSellRequests = list;
      notifyListeners();
    });
    _coinTxSub?.cancel();
    _coinTxSub = _fb.watchCoinTransactions(phone).listen((list) {
      _coinTransactions = list;
      notifyListeners();
    });
  }

  /// Ported from renderTransactionHistoryScreen()'s feedItems merge/sort
  /// (main-coins.js, 2026-07-25 revision): pending AND rejected Buy/Sell
  /// requests, plus confirmed coin transactions — newest first. Rejected
  /// rows carry the admin's `rejectReason` so the customer knows why.
  List<CoinFeedItem> get coinFeed {
    final items = <CoinFeedItem>[];
    for (final p in _coinPurchases) {
      final status = p['status'] as String?;
      final coins = (p['coins'] as num?)?.toInt() ?? 0;
      if (status == 'pending') {
        final time = DateTime.tryParse(p['date'] as String? ?? '')?.millisecondsSinceEpoch ?? 0;
        items.add(CoinFeedItem.pendingBuy(time: time, coins: coins));
      } else if (status == 'rejected') {
        final time = (p['reviewedAt'] as num?)?.toInt() ??
            DateTime.tryParse(p['date'] as String? ?? '')?.millisecondsSinceEpoch ??
            0;
        items.add(CoinFeedItem.rejectedBuy(time: time, coins: coins, rejectReason: p['rejectReason'] as String?));
      }
    }
    for (final s in _coinSellRequests) {
      final status = s['status'] as String?;
      final coins = (s['coins'] as num?)?.toInt() ?? 0;
      final etbAmount = (s['etbAmount'] as num?)?.toDouble() ?? 0;
      if (status == 'pending') {
        final time = DateTime.tryParse(s['date'] as String? ?? '')?.millisecondsSinceEpoch ?? 0;
        items.add(CoinFeedItem.pendingSell(time: time, coins: coins, etbAmount: etbAmount));
      } else if (status == 'rejected') {
        final time = (s['reviewedAt'] as num?)?.toInt() ??
            DateTime.tryParse(s['date'] as String? ?? '')?.millisecondsSinceEpoch ??
            0;
        items.add(CoinFeedItem.rejectedSell(time: time, coins: coins, etbAmount: etbAmount, rejectReason: s['rejectReason'] as String?));
      }
    }
    for (final tx in _coinTransactions) {
      items.add(CoinFeedItem.tx(
        time: (tx['timestamp'] as num?)?.toInt() ?? 0,
        type: tx['type'] as String? ?? '',
        amount: (tx['amount'] as num?)?.toInt() ?? 0,
        orderId: tx['orderId'] as String?,
        orderPercent: (tx['orderPercent'] as num?)?.toInt(),
        // BUGFIX: transfer_out/transfer_in rows used to always show the
        // generic "Sent to another user" label with no indication of who.
        // NOTE: verify this matches whatever key the transfer backend
        // actually writes into the transaction doc — trying the common
        // possibilities here since it isn't in this repo.
        // BUGFIX: confirmed against telegram-worker/worker.js's coinTxLog()
        // calls in the /transferCoins handler — the actual field written
        // is `counterparty` (not toPhone/peerPhone/etc., which were
        // guesses before the worker source was available).
        peerPhone: tx['counterparty'] as String?,
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

  /// Ported from fetchCoinRateData() call inside renderWalletScreen() —
  /// used by the 💱 Wallet screen for its current price + chart.
  Future<CoinRateData> fetchCoinRateData() => _fb.fetchCoinRateData();

  /// Ported from submitSellCoinsRequest() in main-coins.js.
  Future<bool> submitSellCoins({
    required int coins,
    required double sellRate,
    required String paymentMethodLabel,
    required String account,
  }) {
    if (!isAuthenticated) return Future.value(false);
    return _fb.submitSellCoins(
      phone: user!.phone,
      name: user!.name,
      coins: coins,
      sellRate: sellRate,
      paymentMethodLabel: paymentMethodLabel,
      account: account,
    );
  }

  /// Ported from submitTransferCoins() in main-coins.js. Returns null on
  /// success, or an error code ('recipient_not_found',
  /// 'insufficient_balance', 'wrong_password', 'connection_error').
  Future<String?> transferCoins({required String toPhone, required int coins, required String password}) {
    if (!isAuthenticated) return Future.value('not_authenticated');
    return _fb.transferCoins(phone: user!.phone, password: password, toPhone: toPhone, coins: coins);
  }

  /// Ported from submitUpdateName() in main-coins.js. On success, updates
  /// the in-memory user + persisted session (same fields the web app
  /// re-saves to localStorage: name + phone only) and returns the new
  /// name with a null error.
  Future<(String?, String?)> updateName({required String newName, required String password}) async {
    if (!isAuthenticated) return (null, 'not_authenticated');
    final (name, err) = await _fb.updateName(phone: user!.phone, password: password, newName: newName);
    if (err == null && name != null) {
      user = UserModel(name: name, phone: user!.phone);
      await StorageService.saveSession(user!);
      notifyListeners();
    }
    return (name, err);
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

  // ---- Pending state kept while an email verification code is
  // outstanding — mirrors _authRegisterPending/_authMigratePending in
  // main-config.js. Needed so completeRegister()/completeMigrate() and
  // the "resend code" actions know what to finish/resend without asking
  // the user to retype everything.
  _PendingRegister? _pendingRegister;
  _PendingMigrate? _pendingMigrate;

  /// Step 1 of registration — ported from submitAuthRegisterStart() in
  /// main-config.js. Sends the 5-digit email verification code; the
  /// account itself isn't created yet (that happens in completeRegister()
  /// once the code is confirmed). Returns null on success, or an error
  /// code: 'invalid_email', 'invalid_password', 'already_registered',
  /// 'connection_error'.
  Future<String?> startRegister({
    required String name,
    required String phone,
    required String email,
    required String password,
    String? incomingReferralCode,
  }) async {
    final myCode = FirebaseService.generateReferralCode();
    final result = await _fb.sendVerificationCode(
      phone: phone,
      purpose: 'register',
      email: email,
      password: password,
      name: name,
      referralCode: myCode,
    );
    if (!result.ok) return result.error ?? 'connection_error';
    _pendingRegister = _PendingRegister(
      name: name,
      phone: phone,
      email: email,
      password: password,
      myCode: myCode,
      incomingReferralCode: incomingReferralCode,
    );
    return null;
  }

  /// Resends the registration code — ports resendVerifyCode() (register
  /// branch) in main-config.js. Must be called after a successful
  /// startRegister() in the same flow.
  Future<String?> resendRegisterCode() async {
    final p = _pendingRegister;
    if (p == null) return 'connection_error';
    final result = await _fb.sendVerificationCode(
      phone: p.phone,
      purpose: 'register',
      email: p.email,
      password: p.password,
      name: p.name,
      referralCode: p.myCode,
    );
    return result.ok ? null : (result.error ?? 'connection_error');
  }

  /// Step 2 of registration — ported from submitVerifyCode() +
  /// finishRegistrationAfterVerify() in main-config.js. The Worker
  /// creates users/{phone} once the code matches; this then does the
  /// client-only bits that were always client-side: caching the new
  /// promo code and crediting whoever referred this user.
  Future<String?> completeRegister(String code) async {
    final p = _pendingRegister;
    if (p == null) return 'connection_error';
    final result = await _fb.verifyEmailCode(phone: p.phone, code: code, purpose: 'register');
    if (!result.ok) return result.error ?? 'connection_error';
    final userData = result.userData!;

    try {
      await _fb.setReferralIndex(p.myCode, p.phone);

      // 🪙 Signup bonus — ports the awardSignupBonus() call in
      // finishRegistrationAfterVerify() (main-config.js). Updates
      // userData.coins with the post-bonus balance BEFORE logging in, so
      // the new account's first balance shown already includes it
      // instead of appearing to be 0 until a later refresh.
      final newCoins = await _fb.awardSignupBonus(p.phone);
      if (newCoins != null) userData['coins'] = newCoins;

      final incoming = p.incomingReferralCode?.trim().toUpperCase();
      if (incoming != null && incoming.length >= 6 && incoming != p.myCode) {
        final ownerPhone = await _fb.resolveReferralOwner(incoming);
        if (ownerPhone != null) {
          await _fb.trackReferralUse(incoming, p.phone);
          final newCount = await _fb.incrementReferralCount(ownerPhone);
          final withinCap = newCount == null || newCount <= WalletService.maxReferralCountForCoins;
          if (withinCap) {
            await _fb.awardReferralCoins(incoming, ownerPhone, p.phone);
          }
        }
      }
    } catch (_) {
      // Non-fatal — referral crediting failing shouldn't block the new
      // account from logging in, matching the web app's try/catch here.
    }

    _pendingRegister = null;
    await _completeLogin(p.phone, userData);
    return null;
  }

  /// Step 1 of the legacy-account migration flow (add email + new
  /// password) — ports submitAuthMigrateStart() in main-config.js.
  /// Reached when login()/checkPhone() surfaces 'migration_required' for
  /// an existing PIN-only account. Returns null on success (code sent),
  /// or 'invalid_email' / 'invalid_password' / 'connection_error'.
  Future<String?> startMigrate({required String phone, required String email, required String password}) async {
    final result = await _fb.sendVerificationCode(phone: phone, purpose: 'migrate', email: email, password: password);
    if (!result.ok) return result.error ?? 'connection_error';
    _pendingMigrate = _PendingMigrate(phone: phone, email: email, password: password);
    return null;
  }

  /// Resends the migration code — ports resendVerifyCode() (migrate
  /// branch) in main-config.js.
  Future<String?> resendMigrateCode() async {
    final p = _pendingMigrate;
    if (p == null) return 'connection_error';
    final result = await _fb.sendVerificationCode(phone: p.phone, purpose: 'migrate', email: p.email, password: p.password);
    return result.ok ? null : (result.error ?? 'connection_error');
  }

  /// Step 2 of migration — ports the migrate branch of submitVerifyCode()
  /// in main-config.js: the Worker adds email/password to the existing
  /// account and marks it `emailVerified`, then this logs straight in.
  Future<String?> completeMigrate(String code) async {
    final p = _pendingMigrate;
    if (p == null) return 'connection_error';
    final result = await _fb.verifyEmailCode(phone: p.phone, code: code, purpose: 'migrate');
    if (!result.ok) return result.error ?? 'connection_error';
    _pendingMigrate = null;
    await _completeLogin(p.phone, result.userData!);
    return null;
  }

  /// The "ፓስዎርድ ረሳሁ?" flow, step 1 — ports handleForgotSendClick() in
  /// main-config.js. Sends a reset code to the account's email (the
  /// Worker verifies [email] actually matches the account before
  /// sending — the client is never told whether it matched or not up
  /// front, to avoid leaking which email is on file). Returns null on
  /// success, or 'invalid_email' / 'email_mismatch' /
  /// 'migration_required' (legacy account — caller should route to the
  /// migrate step instead) / 'connection_error'.
  Future<String?> sendForgotCode({required String phone, required String email}) async {
    final result = await _fb.sendVerificationCode(phone: phone, purpose: 'reset', email: email);
    return result.ok ? null : (result.error ?? 'connection_error');
  }

  /// The "ፓስዎርድ ረሳሁ?" flow, step 2 — ports submitForgotCodeAndPassword()
  /// in main-config.js. Combines code confirmation + setting the new
  /// password in one call (unlike register/migrate, which verify the
  /// code first and separately). Returns null on success (already logged
  /// in), or 'code_expired' / 'wrong_code' / 'invalid_password' /
  /// 'connection_error'.
  Future<String?> completeForgotPassword({required String phone, required String code, required String newPassword}) async {
    final result = await _fb.verifyEmailCode(phone: phone, code: code, purpose: 'reset', newPassword: newPassword);
    if (!result.ok) return result.error ?? 'connection_error';
    await _completeLogin(phone, result.userData!);
    return null;
  }

  /// Ported from hcSendToAdmin() in main-ui.js — Help Center "Send to
  /// Admin" escalation. Falls back to 'unknown'/'Customer' for a guest,
  /// matching `state.user || {}` in the web app (the web app lets even
  /// an unauthenticated visitor send a support message).
  Future<String?> sendSupportMessage(String message) {
    return _fb.sendSupportMessage(
      phone: user?.phone ?? 'unknown',
      name: user?.name ?? 'Customer',
      message: message,
    );
  }

  /// Ported from confirmCoinPin() in main-coins.js — verifies the
  /// account password server-side (POST /verifyPassword) right when the
  /// coin-redemption checkbox is toggled on, so a wrong password is
  /// caught immediately instead of only failing at final checkout submit.
  Future<String?> verifyPassword(String password) async {
    if (!isAuthenticated) return 'not_authenticated';
    final result = await _fb.verifyPassword(phone: user!.phone, password: password);
    return result.ok ? null : (result.error ?? 'connection_error');
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
    _ordersSub?.cancel();
    _referralSub?.cancel();
    _coinPurchasesSub?.cancel();
    _coinSellRequestsSub?.cancel();
    _coinTxSub?.cancel();
    _coinPurchases = [];
    _coinSellRequests = [];
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
      unawaited(StorageService.saveNotifications(list)); // 2-5: keep the local cache fresh
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

  // ---------------- Orders (2-5 fix — live sync was missing entirely) ----------------

  /// Before this, `orders` was only ever seeded once from the local Hive
  /// cache plus whatever the client itself just wrote locally — a status
  /// change made remotely (e.g. an admin marking an order
  /// Delivered/Rejected) never reached the app. This keeps `orders` live,
  /// same stale-while-revalidate shape as products/notifications: the
  /// screen already paints instantly from `StorageService.loadOrders()`
  /// at bootstrap, and this listener refreshes it (and the cache) the
  /// moment new data arrives.
  void _watchOrders(String phone) {
    _ordersSub?.cancel();
    _ordersSub = _fb.watchOrders(phone).listen((list) {
      orders = list;
      unawaited(StorageService.saveOrders(list));
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
    String? coinPassword,
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
      methodLabel = lang == 'am' ? '100% Coins ተከፍሏል' : '100% Paid with Coins';
    } else if (coinPercent > 0) {
      methodLabel = '$coinPercent% Coins + $methodLabel';
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
    if (coinsUsed > 0 && coinPassword != null) {
      final redeemErr = await redeemCoinsForOrder(
        coinsToUse: coinsUsed,
        cartTotal: rawTotal,
        password: coinPassword,
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
  /// [cartTotal], re-checking [password] server-side. Returns null +
  /// updates [coins] on success, or an error code string on failure —
  /// one of 'not_authenticated', 'wrong_password', 'locked_try_later',
  /// 'out_of_range', 'exceeds_max_usable', or 'redeem_failed'.
  Future<String?> redeemCoinsForOrder({
    required int coinsToUse,
    required double cartTotal,
    required String password,
    String? orderId,
    int? orderPercent,
  }) async {
    if (!isAuthenticated) return 'not_authenticated';
    final result = await _fb.redeemCoins(
      phone: user!.phone,
      password: password,
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

  Future<void> toggleLike(String productId) async {
    if (likes.contains(productId)) {
      likes.remove(productId);
    } else {
      likes.add(productId);
    }
    // Update UI immediately, then persist. Awaiting here (instead of
    // firing-and-forgetting) matters: previously the Hive write could
    // lose the race if the app was backgrounded/killed right after a
    // like, silently reverting to an empty list on next launch.
    notifyListeners();
    await StorageService.saveLikes(likes);
    if (isAuthenticated) _fb.syncLikes(user!.phone, likes);
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
  ///
  /// BUGFIX: this used to ignore `activeCategory`, so e.g. the "Phone"
  /// category page would still show discounted products from every other
  /// category in this strip. Scope it the same way `filteredProducts` is
  /// scoped, so the discounts shown always belong to the category the
  /// person is currently looking at (or all categories, on the "all" tab).
  List<Product> get discountedProducts {
    return products
        .where((p) =>
            !p.hidden &&
            p.discountedPrice != null &&
            p.discountedPrice! < p.price &&
            (activeCategory == 'all' || p.category == activeCategory))
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
    _ordersSub?.cancel();
    _referralSub?.cancel();
    _notifSub?.cancel();
    _coinPurchasesSub?.cancel();
    _coinSellRequestsSub?.cancel();
    _coinTxSub?.cancel();
    super.dispose();
  }
}

/// Ported from the merged feedItems row types in renderTransactionHistoryScreen()
/// (main-coins.js, 2026-07-25 revision): a pending or rejected Buy/Sell
/// request, or a confirmed ledger entry (earn/redeem/admin adjustment).
enum CoinFeedKind { pendingBuy, pendingSell, rejectedBuy, rejectedSell, tx }

class CoinFeedItem {
  final int time;
  final CoinFeedKind kind;
  final int coins; // buy/sell rows — the coin amount requested
  final double etbAmount; // sell rows only — ETB the customer will receive
  final String? rejectReason; // rejected rows only — admin's comment

  final String type; // tx only
  final int amount; // tx only — signed (+credit / -debit)
  final String? orderId; // tx only, redeem rows
  final int? orderPercent; // tx only, redeem rows
  final String? peerPhone; // tx only, transfer_in/transfer_out rows — the other party's phone number

  bool get isPending => kind == CoinFeedKind.pendingBuy || kind == CoinFeedKind.pendingSell;
  bool get isRejected => kind == CoinFeedKind.rejectedBuy || kind == CoinFeedKind.rejectedSell;

  CoinFeedItem.pendingBuy({required this.time, required this.coins})
      : kind = CoinFeedKind.pendingBuy,
        etbAmount = 0,
        rejectReason = null,
        type = '',
        amount = 0,
        orderId = null,
        orderPercent = null,
        peerPhone = null;

  CoinFeedItem.pendingSell({required this.time, required this.coins, required this.etbAmount})
      : kind = CoinFeedKind.pendingSell,
        rejectReason = null,
        type = '',
        amount = 0,
        orderId = null,
        orderPercent = null,
        peerPhone = null;

  CoinFeedItem.rejectedBuy({required this.time, required this.coins, this.rejectReason})
      : kind = CoinFeedKind.rejectedBuy,
        etbAmount = 0,
        type = '',
        amount = 0,
        orderId = null,
        orderPercent = null,
        peerPhone = null;

  CoinFeedItem.rejectedSell({required this.time, required this.coins, required this.etbAmount, this.rejectReason})
      : kind = CoinFeedKind.rejectedSell,
        type = '',
        amount = 0,
        orderId = null,
        orderPercent = null,
        peerPhone = null;

  CoinFeedItem.tx({required this.time, required this.type, required this.amount, this.orderId, this.orderPercent, this.peerPhone})
      : kind = CoinFeedKind.tx,
        coins = 0,
        etbAmount = 0,
        rejectReason = null;
}

/// Held between startRegister() and completeRegister()/resendRegisterCode()
/// — mirrors _authRegisterPending in main-config.js.
class _PendingRegister {
  final String name;
  final String phone;
  final String email;
  final String password;
  final String myCode;
  final String? incomingReferralCode;

  _PendingRegister({
    required this.name,
    required this.phone,
    required this.email,
    required this.password,
    required this.myCode,
    this.incomingReferralCode,
  });
}

/// Held between startMigrate() and completeMigrate()/resendMigrateCode()
/// — mirrors _authMigratePending in main-config.js.
class _PendingMigrate {
  final String phone;
  final String email;
  final String password;

  _PendingMigrate({required this.phone, required this.email, required this.password});
}
