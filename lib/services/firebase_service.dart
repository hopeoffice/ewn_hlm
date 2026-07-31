import 'dart:math';

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/category.dart';
import '../models/coin_rate_model.dart';
import 'wallet_service.dart';

/// Step 1 of the migration plan: same two databases the web app already
/// uses, called with the native Flutter SDKs instead of firebase-init.js's
/// compat SDK. No schema change — this reads/writes the exact same paths.
class FirebaseService {
  final _fs = FirebaseFirestore.instance;
  final _rtdb = FirebaseDatabase.instance;

  // Same worker as the PWA's config.js (telegramReceiptFunctionUrl /
  // telegramMessageFunctionUrl / adminVerifyUrl all share this base).
  static const String workerBaseUrl = 'https://ewn-hlm-telegram.hopeoffice.workers.dev';

  // ---------------- Products (Firestore, real-time — no TTL) ----------------

  /// Equivalent of `__EWN_FS__.collection('products').onSnapshot(...)`
  /// in main-render.js. Consumed with a StreamBuilder in the UI; the
  /// offline fallback (StorageService.loadCachedProducts) is used only
  /// when this stream errors out or the device has no network at all.
  Stream<List<Product>> watchProducts() {
    return _fs.collection('products').snapshots().map((snap) => snap.docs
        .map((d) => Product.fromMap(d.id, d.data()))
        .where((p) => !p.hidden)
        .toList());
  }

  // ---------------- Categories (admin-managed, Realtime DB, one-time read) ----------------

  /// Mirrors loadCategoriesFromFirebase() in main-config.js: reads the
  /// admin panel's `settings/categories` list once. Returns null (not an
  /// empty list) when Firebase has nothing there yet or the read fails,
  /// so the caller (AppState) knows to fall back to the local cache /
  /// static defaults instead of wiping out a previously-known good list.
  /// "all" is intentionally NOT included here — AppState pins it first.
  Future<List<AppCategory>?> fetchCategories() async {
    try {
      final snap = await _rtdb.ref('settings/categories').get();
      final data = snap.value;
      if (data is List && data.isNotEmpty) {
        return data
            .whereType<Map>()
            .map((c) => AppCategory.fromMap(c))
            .toList();
      }
      if (data is Map && data.isNotEmpty) {
        // Realtime DB can also serialize a JS array as a keyed map.
        return data.values.whereType<Map>().map((c) => AppCategory.fromMap(c)).toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Ported from loadFaqFromFirebase() in main-ui.js: reads the Help
  /// Center FAQ list from `settings/faq` once. Returns null (not an
  /// empty list) on failure or when nothing's there, so the caller
  /// (HelpCenterScreen) falls back to the bundled assets/faq_data.json
  /// — same fallback order as the web app, so FAQ edits made in the
  /// admin panel show up in the app without a store release.
  Future<List<Map<String, dynamic>>?> fetchFaqs() async {
    try {
      final snap = await _rtdb.ref('settings/faq').get();
      final data = snap.value;
      if (data is Map && data.isNotEmpty) {
        return data.entries
            .map((e) => {'id': e.key.toString(), ...Map<String, dynamic>.from(e.value as Map)})
            .toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Ported from the requestLocationPermission() Realtime DB write in
  /// main-actions.js: users/{phone}/location, Realtime DB only (never
  /// Firestore).
  Future<void> saveLocation(String phone, Map<String, dynamic> location) {
    return _rtdb.ref('users/$phone/location').set(location);
  }

  /// Ported from loadPaymentAccountsFromDb() in main-actions.js. Admin can
  /// override the fallback account numbers via settings/paymentAccounts;
  /// returns null (keep fallbacks) if nothing is set or the read fails.
  Future<Map<String, String>?> fetchPaymentAccounts() async {
    try {
      final snap = await _rtdb.ref('settings/paymentAccounts').get();
      final data = snap.value;
      if (data is Map) {
        return data.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---------------- Users (custom phone+PIN auth, Realtime DB) ----------------

  /// Reads users/{phone} — mirrors the PIN check done client-side in
  /// main-config.js's login flow. NOTE: for production, PIN comparison
  /// should ideally move server-side (Cloudflare Worker) exactly like
  /// /verifyAdminPassword already does for the admin panel — flagged here
  /// as a follow-up, not changed in this migration to keep behaviour 1:1.
  Future<Map<String, dynamic>?> fetchUser(String phone) async {
    final snap = await _rtdb.ref('users/$phone').get();
    if (!snap.exists) return null;
    return Map<String, dynamic>.from(snap.value as Map);
  }

  Future<void> createUser(String phone, Map<String, dynamic> data) async {
    await _rtdb.ref('users/$phone').set(data);
  }

  Future<void> updateUserFields(String phone, Map<String, dynamic> fields) async {
    await _rtdb.ref('users/$phone').update(fields);
  }

  // ---------------- Cart / Likes (debounced sync, main-config.js saveCart/saveLikes) ----------------

  Timer? _cartSyncTimer;

  void syncCartDebounced(String phone, List<CartItem> cart) {
    _cartSyncTimer?.cancel();
    _cartSyncTimer = Timer(const Duration(milliseconds: 400), () {
      _rtdb.ref('users/$phone/cart').set(cart.map((c) => c.toMap()).toList());
    });
  }

  Future<void> syncLikes(String phone, List<String> likes) {
    return _rtdb.ref('users/$phone/likes').set(likes);
  }

  // ---------------- Orders ----------------

  /// Mirrors saveOrderToFirebase(): writes to orders/{id} AND mirrors
  /// under the user's own record so "my orders" works cross-device.
  Future<void> saveOrder(String phone, Map<String, dynamic> order) async {
    final id = order['id'] as String;
    await _rtdb.ref('orders/$id').set(order);
    await _rtdb.ref('users/$phone/orders/$id').set(order);
  }

  /// BUGFIX (2-5): there was no live listener for orders at all before —
  /// the local `orders` list was only ever seeded once from Hive at app
  /// start and appended to when the user placed a new order locally, so a
  /// status change made remotely (e.g. an admin marking an order
  /// Delivered/Rejected) never reached the app. Mirrors watchNotifications()
  /// above: a live users/{phone}/orders listener, newest-first.
  Stream<List<Map<String, dynamic>>> watchOrders(String phone) {
    return _rtdb.ref('users/$phone/orders').onValue.map((event) {
      final val = event.snapshot.value;
      final list = <Map<String, dynamic>>[];
      if (val is Map) {
        val.forEach((key, v) {
          if (v is Map) list.add(Map<String, dynamic>.from(v));
        });
      }
      list.sort((a, b) {
        final da = DateTime.tryParse(a['date']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
        final db = DateTime.tryParse(b['date']?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
        return da.compareTo(db); // oldest-first, matching the existing "newest first" reversal at render time
      });
      return list;
    });
  }

  // ---------------- Coin balance (main-coins.js: userData.coins) ----------------

  /// Live coin balance — users/{phone}/coins. There is only ONE real
  /// balance field in the DB (per the comment in main-coins.js); "bonus"
  /// and "savings" shown in the UI are client-side estimates, not
  /// separate stored numbers.
  Stream<int> watchCoinBalance(String phone) {
    return _rtdb.ref('users/$phone/coins').onValue.map((event) {
      final v = event.snapshot.value;
      return (v is num) ? v.toInt() : 0;
    });
  }

  // ---------------- Coin purchases / transaction history (main-coins.js) ----------------

  /// Ported from submitBuyCoins(): writes the pending request to
  /// coinPurchases/{id} (admin-read-only) AND mirrors it under the user's
  /// own node so it shows up in Transaction History immediately, then
  /// notifies Telegram with the receipt photo for admin approval.
  Future<bool> submitBuyCoins({
    required String phone,
    required String name,
    required double amountETB,
    required int coins,
    required String paymentMethodLabel,
    required List<int> receiptBytes,
    required String receiptFilename,
  }) async {
    final id = 'COIN-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    final purchase = {
      'id': id,
      'phone': phone,
      'name': name,
      'amountETB': amountETB,
      'coins': coins,
      'paymentMethod': paymentMethodLabel,
      'status': 'pending',
      'date': DateTime.now().toIso8601String(),
    };
    try {
      await _rtdb.ref('coinPurchases/$id').set(purchase);
      unawaited(_rtdb.ref('users/$phone/coinPurchaseMirror/$id').set(purchase));

      final caption = [
        '🪙 የ coin ግዢ ጥያቄ / Coin Purchase Request',
        '',
        '🆔 ID: $id',
        '👤 ደንበኛ: $name ($phone)',
        '💳 ክፍያ: $paymentMethodLabel',
        '💰 የከፈሉት: $amountETB ETB',
        '🪙 የሚያገኙት: $coins Coins',
      ].join('\n');
      await sendReceiptToTelegram(caption: caption, receiptBytes: receiptBytes, filename: receiptFilename);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ported from renderTransactionHistoryScreen()'s two parallel reads —
  /// pending purchase requests. Filtering to status=='pending' (approved
  /// ones show up via watchCoinTransactions() instead, as a
  /// purchase_approved row) is the caller's job (AppState), same as the
  /// web app's `if (p.status === 'pending')` check.
  Stream<List<Map<String, dynamic>>> watchCoinPurchases(String phone) {
    return _rtdb.ref('users/$phone/coinPurchaseMirror').onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return <Map<String, dynamic>>[];
      return v.entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['id'] = e.key;
        return m;
      }).toList();
    });
  }

  /// Mirrors watchCoinPurchases() above but for Sell Coins requests
  /// (`users/{phone}/sellRequestMirror`) — added so the 💱 Wallet
  /// screen's Sell action shows up as pending/rejected in the feed too.
  Stream<List<Map<String, dynamic>>> watchCoinSellRequests(String phone) {
    return _rtdb.ref('users/$phone/sellRequestMirror').onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return <Map<String, dynamic>>[];
      return v.entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['id'] = e.key;
        return m;
      }).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> watchCoinTransactions(String phone) {
    return _rtdb.ref('users/$phone/coinTxMirror').onValue.map((event) {
      final v = event.snapshot.value;
      if (v is! Map) return <Map<String, dynamic>>[];
      return v.entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['id'] = e.key;
        return m;
      }).toList();
    });
  }

  // ---------------- Notifications (Realtime DB, main-render.js initNotificationsListener) ----------------

  /// Merges global broadcast notifications (`notifications`, all users)
  /// with personal ones (`users/{phone}/notifications`), de-duplicated by
  /// id and sorted newest-first — same as mergeAndRender() in main-render.js.
  /// Emits a fresh combined list every time either branch changes.
  Stream<List<Map<String, dynamic>>> watchNotifications({String? phone}) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    List<Map<String, dynamic>> global = [];
    List<Map<String, dynamic>> personal = [];

    void emit() {
      final merged = [...global, ...personal];
      final seen = <String>{};
      final deduped = merged.where((n) {
        final id = n['id'] as String;
        if (seen.contains(id)) return false;
        seen.add(id);
        return true;
      }).toList();
      deduped.sort((a, b) {
        final ta = (a['timestamp'] as num?)?.toInt() ??
            DateTime.tryParse(a['date']?.toString() ?? '')?.millisecondsSinceEpoch ??
            0;
        final tb = (b['timestamp'] as num?)?.toInt() ??
            DateTime.tryParse(b['date']?.toString() ?? '')?.millisecondsSinceEpoch ??
            0;
        return tb.compareTo(ta);
      });
      controller.add(deduped);
    }

    final globalSub = _rtdb
        .ref('notifications')
        .orderByChild('timestamp')
        .limitToLast(50)
        .onValue
        .listen((event) {
      global = [];
      final val = event.snapshot.value;
      if (val is Map) {
        val.forEach((key, v) {
          global.add({'id': key.toString(), ...Map<String, dynamic>.from(v as Map)});
        });
      }
      emit();
    });

    StreamSubscription<DatabaseEvent>? personalSub;
    if (phone != null) {
      personalSub = _rtdb
          .ref('users/$phone/notifications')
          .orderByChild('timestamp')
          .limitToLast(30)
          .onValue
          .listen((event) {
        personal = [];
        final val = event.snapshot.value;
        if (val is Map) {
          val.forEach((key, v) {
            personal.add({
              'id': key.toString(),
              ...Map<String, dynamic>.from(v as Map),
              'personal': true,
            });
          });
        }
        emit();
      });
    }

    controller.onCancel = () {
      globalSub.cancel();
      personalSub?.cancel();
    };

    return controller.stream;
  }

  // ---------------- Device linking (fraud guard) ----------------
  // Matches the real database_rules.json: only users/{phone}/deviceId
  // is client-writable (there is no top-level "deviceLinks" node).
  Future<void> linkDeviceToUser(String phone, String deviceId) {
    return _rtdb.ref('users/$phone/deviceId').set(deviceId);
  }

  // ---------------- Cloudflare Worker calls (unchanged backend) ----------------

  Future<bool> awardReferralCoins(String code, String ownerPhone, String newUserPhone) async {
    final res = await http.post(
      Uri.parse('$workerBaseUrl/awardReferralCoins'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'ownerPhone': ownerPhone, 'newUserPhone': newUserPhone}),
    );
    return res.statusCode == 200;
  }

  /// Ported from handleAwardSignupBonus() in worker.js. Returns the new
  /// coin balance on success (null on failure) so the caller can show the
  /// bonus-included balance immediately without a separate fetch.
  Future<int?> awardSignupBonus(String phone) async {
    try {
      final res = await http.post(
        Uri.parse('$workerBaseUrl/awardSignupBonus'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['ok'] == true) {
        return (body['coins'] as num?)?.toInt();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Ported from handleRedeemCoins() in worker.js. This is the ONLY way
  /// coins get spent — always at checkout, always PIN-gated server-side.
  /// [cartTotal] must be the ETB total of the order being placed (the
  /// worker rejects redemption if this is below MIN_REDEEM_ETB, and caps
  /// coinsToUse at etbToCoins(cartTotal) regardless of what's requested).
  /// [orderId]/[orderPercent] are optional, purely descriptive — shown in
  /// Transaction History, never trusted for balance math.
  Future<RedeemCoinsResult> redeemCoins({
    required String phone,
    required String password,
    required int coinsToUse,
    required double cartTotal,
    String? orderId,
    int? orderPercent,
  }) async {
    final res = await http.post(
      Uri.parse('$workerBaseUrl/redeemCoins'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'password': password,
        'coinsToUse': coinsToUse,
        'cartTotal': cartTotal,
        if (orderId != null) 'orderId': orderId,
        if (orderPercent != null) 'orderPercent': orderPercent,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return RedeemCoinsResult(
      ok: body['ok'] == true,
      error: body['error'] as String?,
      coins: (body['coins'] as num?)?.toInt(),
      discountETB: (body['discountETB'] as num?)?.toDouble(),
      maxUsable: (body['maxUsable'] as num?)?.toInt(),
    );
  }

  /// Ported from submitAuthLogin() in main-config.js — POST /login.
  /// Password is verified server-side (PBKDF2 hash comparison + 5-wrong/
  /// 15-min lockout); the client never holds or compares the hash.
  /// Errors: 'wrong_password', 'account_blocked', 'locked_try_later',
  /// 'user_not_found', or 'migration_required' (legacy PIN-only account —
  /// caller should route to the migrate step, not show this as an error).
  Future<AuthResult> loginWithPassword({required String phone, required String password}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$workerBaseUrl/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'password': password}),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['ok'] == true) {
        return AuthResult(ok: true, userData: Map<String, dynamic>.from(body['userData'] as Map));
      }
      return AuthResult(ok: false, error: body['error'] as String?);
    } catch (_) {
      return AuthResult(ok: false, error: 'connection_error');
    }
  }

  /// Ported from requestVerificationCode() in main-config.js — POST
  /// /sendVerificationCode. [purpose] is one of 'register', 'migrate', or
  /// 'reset'. [email]/[password]/[name]/[referralCode] are required for
  /// 'register' and 'migrate' but not 'reset' (which only needs the
  /// account's own phone + the email to confirm it matches).
  /// Errors: 'invalid_email', 'invalid_password', 'already_registered',
  /// 'email_mismatch', 'blocked' (resend rate-limit hit — caller should
  /// disable the resend button, not just show an error).
  Future<AuthResult> sendVerificationCode({
    required String phone,
    required String purpose,
    String? email,
    String? password,
    String? name,
    String? referralCode,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$workerBaseUrl/sendVerificationCode'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'purpose': purpose,
              if (email != null) 'email': email,
              if (password != null) 'password': password,
              if (name != null) 'name': name,
              if (referralCode != null) 'referralCode': referralCode,
            }),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return AuthResult(ok: res.statusCode == 200 && body['ok'] == true, error: body['error'] as String?);
    } catch (_) {
      return AuthResult(ok: false, error: 'connection_error');
    }
  }

  /// Ported from submitVerifyCode()/submitForgotCodeAndPassword() in
  /// main-config.js — POST /verifyEmailCode. [newPassword] only applies
  /// when [purpose] == 'reset'. Returns the finalized `userData` on
  /// success for 'register'/'migrate'/'reset' alike (used to log straight
  /// in afterward). Errors: 'code_expired', 'wrong_code'.
  Future<AuthResult> verifyEmailCode({
    required String phone,
    required String code,
    required String purpose,
    String? newPassword,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$workerBaseUrl/verifyEmailCode'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'code': code,
              'purpose': purpose,
              if (newPassword != null) 'newPassword': newPassword,
            }),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['ok'] == true) {
        return AuthResult(ok: true, userData: Map<String, dynamic>.from(body['userData'] as Map));
      }
      return AuthResult(ok: false, error: body['error'] as String?);
    } catch (_) {
      return AuthResult(ok: false, error: 'connection_error');
    }
  }

  /// Ported from confirmCoinPin() in main-coins.js — POST /verifyPassword.
  /// Used right before letting the coin-redemption checkbox turn on, so a
  /// wrong password is caught immediately rather than only at final
  /// checkout submission.
  Future<AuthResult> verifyPassword({required String phone, required String password}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$workerBaseUrl/verifyPassword'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'password': password}),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return AuthResult(ok: res.statusCode == 200 && body['ok'] == true, error: body['error'] as String?);
    } catch (_) {
      return AuthResult(ok: false, error: 'connection_error');
    }
  }

  /// Ported from fetchCoinRateData() in main-coins.js — reads
  /// `coinRates/current` (admin-set buy/sell rate) and the last
  /// [WalletService.walletHistoryLimit] entries of `coinRates/history`.
  /// Falls back to [WalletService.coinValueEtb]-based rates (same as the
  /// web app's `fallbackCurrent`) if either read fails or is empty, so
  /// the Wallet screen always has *something* to render its chart from.
  Future<CoinRateData> fetchCoinRateData() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fallbackCurrent = CoinRateSnapshot(
      buyRate: WalletService.coinValueEtb,
      sellRate: double.parse((WalletService.coinValueEtb * 0.9).toStringAsFixed(4)),
      updatedAt: now,
    );
    try {
      final curSnap = await _rtdb.ref('coinRates/current').get();
      final histSnap = await _rtdb
          .ref('coinRates/history')
          .orderByKey()
          .limitToLast(WalletService.walletHistoryLimit)
          .get();

      CoinRateSnapshot current = fallbackCurrent;
      if (curSnap.exists && curSnap.value is Map) {
        final m = Map<String, dynamic>.from(curSnap.value as Map);
        current = CoinRateSnapshot(
          buyRate: (m['buyRate'] as num?)?.toDouble() ?? fallbackCurrent.buyRate,
          sellRate: (m['sellRate'] as num?)?.toDouble() ?? fallbackCurrent.sellRate,
          updatedAt: (m['updatedAt'] as num?)?.toInt() ?? now,
        );
      }

      final history = <CoinRatePoint>[];
      if (histSnap.exists && histSnap.value is Map) {
        final m = Map<String, dynamic>.from(histSnap.value as Map);
        for (final entry in m.entries) {
          final v = Map<String, dynamic>.from(entry.value as Map);
          history.add(CoinRatePoint(
            ts: int.tryParse(entry.key) ?? now,
            buyRate: (v['buyRate'] as num?)?.toDouble() ?? current.buyRate,
            sellRate: (v['sellRate'] as num?)?.toDouble() ?? current.sellRate,
          ));
        }
        history.sort((a, b) => a.ts.compareTo(b.ts));
      }
      if (history.isEmpty) {
        history.add(CoinRatePoint(ts: now - 24 * 60 * 60 * 1000, buyRate: current.buyRate, sellRate: current.sellRate));
        history.add(CoinRatePoint(ts: now, buyRate: current.buyRate, sellRate: current.sellRate));
      }
      return CoinRateData(current: current, history: history);
    } catch (_) {
      return CoinRateData(current: fallbackCurrent, history: [
        CoinRatePoint(ts: now - 1, buyRate: fallbackCurrent.buyRate, sellRate: fallbackCurrent.sellRate),
        CoinRatePoint(ts: now, buyRate: fallbackCurrent.buyRate, sellRate: fallbackCurrent.sellRate),
      ]);
    }
  }

  /// Ported from submitSellCoinsRequest() in main-coins.js — like Buy
  /// Coins, this is a "pending request, admin approves" write (the
  /// client can never deduct its own coin balance directly per
  /// database_rules.json), plus a text-only Telegram notification
  /// (ported from sendSellRequestToTelegram()).
  Future<bool> submitSellCoins({
    required String phone,
    required String name,
    required int coins,
    required double sellRate,
    required String paymentMethodLabel,
    required String account,
  }) async {
    final id = 'SELL-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';
    final etbAmount = double.parse((coins * sellRate).toStringAsFixed(2));
    final request = {
      'id': id,
      'phone': phone,
      'name': name,
      'coins': coins,
      'sellRate': sellRate,
      'etbAmount': etbAmount,
      'paymentMethod': paymentMethodLabel,
      'account': account,
      'status': 'pending',
      'date': DateTime.now().toIso8601String(),
    };
    try {
      await _rtdb.ref('coinSellRequests/$id').set(request);
      unawaited(_rtdb.ref('users/$phone/sellRequestMirror/$id').set(request));

      final text = [
        '🪙 የ coin ሽያጭ ጥያቄ / Coin Sell Request',
        '',
        '🆔 ID: $id',
        '👤 ደንበኛ: $name ($phone)',
        '🪙 የሚሸጡት: $coins Coins',
        '💰 የሚከፈላቸው: $etbAmount ETB',
        '💳 ወደ: $paymentMethodLabel — $account',
      ].join('\n');
      await sendTelegramMessage(text);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ported from submitTransferCoins() in main-coins.js — user-to-user,
  /// immediate (no admin approval needed, unlike Buy/Sell), enforced
  /// entirely server-side by the Worker (`POST /transferCoins`) which
  /// re-verifies the password and re-checks the balance itself.
  /// Returns null on success, or one of: 'recipient_not_found',
  /// 'insufficient_balance', 'wrong_password', 'connection_error'.
  Future<String?> transferCoins({
    required String phone,
    required String password,
    required String toPhone,
    required int coins,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$workerBaseUrl/transferCoins'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'password': password, 'toPhone': toPhone, 'coins': coins}),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['ok'] == true) return null;
      return (body['error'] as String?) ?? 'connection_error';
    } catch (_) {
      return 'connection_error';
    }
  }

  /// Ported from submitUpdateName() in main-coins.js — POST /updateName.
  /// Returns (newName, null) on success, or (null, errorCode) — one of
  /// 'cooldown_active', 'wrong_password', 'invalid_name', 'user_not_found',
  /// 'locked_try_later', 'connection_error'.
  Future<(String?, String?)> updateName({required String phone, required String password, required String newName}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$workerBaseUrl/updateName'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'password': password, 'newName': newName}),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['ok'] == true) {
        return (body['name'] as String?, null);
      }
      return (null, (body['error'] as String?) ?? 'connection_error');
    } catch (_) {
      return (null, 'connection_error');
    }
  }

  Future<void> sendTelegramMessage(String text) {
    return http.post(
      Uri.parse('$workerBaseUrl/sendTelegramMessage'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
  }

  /// Ported from sendReceiptToTelegram() in main-render.js — sends the
  /// screenshot of a bank/Telebirr transfer as a photo+caption. Used when
  /// the order isn't 100% covered by coins. Telegram caption max = 1024
  /// chars, same truncation as the JS version.
  Future<bool> sendReceiptToTelegram({
    required String caption,
    required List<int> receiptBytes,
    required String filename,
  }) async {
    final uri = Uri.parse('$workerBaseUrl/sendTelegramReceipt');
    final request = http.MultipartRequest('POST', uri)
      ..fields['caption'] = caption.length > 1024 ? caption.substring(0, 1024) : caption
      ..files.add(http.MultipartFile.fromBytes('photo', receiptBytes, filename: filename));
    final streamed = await request.send();
    return streamed.statusCode == 200;
  }

  /// Ported from sendOrderNotificationToTelegram() — text-only order
  /// notice, used for coin-only orders that have no receipt to attach.
  /// Telegram text max = 4096 chars.
  Future<bool> sendOrderNotificationToTelegram(String text) async {
    final res = await http.post(
      Uri.parse('$workerBaseUrl/sendTelegramMessage'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text.length > 4096 ? text.substring(0, 4096) : text}),
    );
    return res.statusCode == 200;
  }

  // ---------------- Referral (index.html getMyReferralCode + main-config.js registration block) ----------------

  static const _referralChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // same alphabet as the JS version
  static final _rand = Random.secure();

  static String generateReferralCode() =>
      List.generate(8, (_) => _referralChars[_rand.nextInt(_referralChars.length)]).join();

  /// users/{phone}/referralCode — created at registration, but this also
  /// covers accounts that predate the referral feature (mirrors the
  /// "already registered user, code missing" branch in getMyReferralCode()).
  Future<String> getOrCreateReferralCode(String phone) async {
    final snap = await _rtdb.ref('users/$phone/referralCode').get();
    if (snap.exists && snap.value != null) return snap.value as String;

    final code = generateReferralCode();
    await _rtdb.ref('users/$phone/referralCode').set(code);
    await _rtdb.ref('referralIndex/$code').set(phone);
    return code;
  }

  Future<void> setReferralIndex(String code, String phone) {
    return _rtdb.ref('referralIndex/$code').set(phone);
  }

  /// referralIndex/{code} → owning phone number, or null if the code
  /// doesn't exist.
  Future<String?> resolveReferralOwner(String code) async {
    final snap = await _rtdb.ref('referralIndex/$code').get();
    return snap.exists ? snap.value as String : null;
  }

  Future<void> trackReferralUse(String code, String newUserPhone) {
    return _rtdb.ref('referrals/$code/uses/$newUserPhone').set(ServerValue.timestamp);
  }

  /// Atomic +1, same as the JS `countRef.transaction(current => (current||0)+1)`.
  /// Returns the new count, or null if the transaction didn't commit.
  Future<int?> incrementReferralCount(String ownerPhone) async {
    final result = await _rtdb.ref('users/$ownerPhone/referralCount').runTransaction((current) {
      final n = (current as int?) ?? 0;
      return Transaction.success(n + 1);
    });
    return result.committed ? (result.snapshot.value as int?) : null;
  }

  Stream<int> watchReferralCount(String phone) {
    return _rtdb.ref('users/$phone/referralCount').onValue.map((event) {
      final v = event.snapshot.value;
      return (v is num) ? v.toInt() : 0;
    });
  }

  // ---------------- Push notifications (Step 3) ----------------

  /// Saves the FCM token under users/{phone}/fcmToken so the Cloudflare
  /// Worker / any future admin tool can target this device directly.
  ///
  /// ⚠️ NOT in the current database_rules.json whitelist (only location,
  /// cart, orders, deviceId, referralCount are client-writable under
  /// users/{phone}) — this write WILL be denied until you add:
  ///   "fcmToken": { ".write": true }
  /// under "users" → "$phone" in Firebase Console → Realtime Database →
  /// Rules, then Publish. Callers must not let this crash the app — see
  /// the try/catch in PushService.registerForUser().
  Future<void> saveFcmToken(String phone, String token) {
    return _rtdb.ref('users/$phone/fcmToken').set(token);
  }

  // ---------------- Help Center → Admin escalation ----------------

  /// Ported from hcSendToAdmin() in main-ui.js: pushes the message to
  /// `support/{pushId}` and enforces a 24h-per-phone rate limit via
  /// `support_limit/{phone}` (a plain millisecond timestamp, same as the
  /// web app — so the limit is shared/consistent across both apps for
  /// the same account). Returns 'rate_limited' if the user already sent
  /// one today, null on success, or 'error' on any other failure.
  Future<String?> sendSupportMessage({
    required String phone,
    required String name,
    required String message,
  }) async {
    try {
      final limitSnap = await _rtdb.ref('support_limit/$phone').get();
      if (limitSnap.exists) {
        final last = (limitSnap.value as num).toInt();
        if (DateTime.now().millisecondsSinceEpoch - last < 24 * 60 * 60 * 1000) {
          return 'rate_limited';
        }
      }

      await _rtdb.ref('support').push().set({
        'phone': phone,
        'name': name,
        'message': message,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'read': false,
      });
      await _rtdb.ref('support_limit/$phone').set(DateTime.now().millisecondsSinceEpoch);
      return null;
    } catch (_) {
      return 'error';
    }
  }
}

/// Result of FirebaseService.redeemCoins() — mirrors the JSON shape
/// returned by handleRedeemCoins() in worker.js. [error] is one of:
/// 'invalid_phone', 'invalid_amount', 'user_not_found', 'locked_try_later',
/// 'wrong_pin', 'out_of_range', 'exceeds_max_usable', or 'internal_error'.
class RedeemCoinsResult {
  final bool ok;
  final String? error;
  final int? coins; // new balance, only present when ok == true
  final double? discountETB; // only present when ok == true
  final int? maxUsable; // only present when error == 'exceeds_max_usable'

  RedeemCoinsResult({required this.ok, this.error, this.coins, this.discountETB, this.maxUsable});
}

/// Generic result for the email/password auth endpoints (login,
/// sendVerificationCode, verifyEmailCode, verifyPassword). [userData] is
/// only present for loginWithPassword()/verifyEmailCode() successes — the
/// finalized user record to log in with. [error] is one of:
/// 'wrong_password', 'account_blocked', 'locked_try_later',
/// 'migration_required', 'already_registered', 'invalid_email',
/// 'invalid_password', 'email_mismatch', 'code_expired', 'wrong_code',
/// 'cooldown', 'blocked', 'user_not_found', 'connection_error'.
class AuthResult {
  final bool ok;
  final String? error;
  final Map<String, dynamic>? userData;

  AuthResult({required this.ok, this.error, this.userData});
}
