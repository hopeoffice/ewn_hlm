import 'dart:math';

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/category.dart';

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

  Future<bool> awardSignupBonus(String phone) async {
    final res = await http.post(
      Uri.parse('$workerBaseUrl/awardSignupBonus'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );
    return res.statusCode == 200;
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
    required String pin,
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
        'pin': pin,
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

  /// Ported from handleResetPin() in worker.js — the "ፓስዎርድ ረሳሁ?" flow.
  /// [securityAnswer] is compared case-insensitively server-side against
  /// what was stored at registration; the local comparison in the UI is
  /// just for instant feedback and is never trusted on its own.
  Future<ResetPinResult> resetPin({
    required String phone,
    required String securityAnswer,
    required String newPin,
  }) async {
    final res = await http.post(
      Uri.parse('$workerBaseUrl/resetPin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'securityAnswer': securityAnswer.toLowerCase(),
        'newPin': newPin,
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return ResetPinResult(ok: body['ok'] == true, error: body['error'] as String?);
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

/// Result of FirebaseService.resetPin() — mirrors handleResetPin() in
/// worker.js. [error] is one of: 'invalid_phone', 'invalid_pin',
/// 'locked_try_later', 'user_not_found', 'wrong_answer', or 'internal_error'.
class ResetPinResult {
  final bool ok;
  final String? error;

  ResetPinResult({required this.ok, this.error});
}
