import 'dart:math';

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../models/cart_item.dart';

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

  // ---------------- Device linking (fraud guard, main-coins.js) ----------------

  Future<void> linkDeviceToUser(String phone, String deviceId) {
    return _rtdb.ref('deviceLinks/$deviceId').set(phone);
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

  Future<bool> redeemCoins(String phone, int coins) async {
    final res = await http.post(
      Uri.parse('$workerBaseUrl/redeemCoins'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'coins': coins}),
    );
    return res.statusCode == 200;
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
  Future<void> saveFcmToken(String phone, String token) {
    return _rtdb.ref('users/$phone/fcmToken').set(token);
  }
}
