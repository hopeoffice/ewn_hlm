import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/user_model.dart';

/// Step 4 of the migration plan — two tiers, exactly matching what the
/// live app already does (verified in main-config.js / main-coins.js):
///
///  A) LOGIN SESSION — no expiry, cleared only on explicit logout().
///     Web app used plain localStorage['ewn_user']; here we upgrade it to
///     flutter_secure_storage (encrypted) for the same "persist forever
///     until logout" behaviour.
///
///  B) CART / LIKES / ORDERS / PRODUCT-CACHE / DEVICE-ID — Hive boxes.
///     Product cache has NO manual TTL, same as the JS version: it is
///     only ever read as an *offline fallback*, while the live price
///     always comes from the Firestore stream when online. This avoids
///     ever showing a stale price to someone who has a connection.
class StorageService {
  static const _secure = FlutterSecureStorage();
  static const _sessionKey = 'ewn_user';

  static late Box _box; // generic box: cart, likes, orders, device id, products cache

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox('ewn_hlm_box');
  }

  // ---------------- A) Login session (secure, no TTL) ----------------

  static Future<void> saveSession(UserModel user) async {
    await _secure.write(key: _sessionKey, value: jsonEncode(user.toMap()));
  }

  static Future<UserModel?> restoreSession() async {
    final raw = await _secure.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      return UserModel.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSession() async {
    await _secure.delete(key: _sessionKey);
  }

  // ---------------- B) Cart ----------------

  static List<CartItem> loadCart() {
    final raw = _box.get('ewn_cart');
    if (raw == null) return [];
    final list = (jsonDecode(raw as String) as List).cast<Map<String, dynamic>>();
    return list.map(CartItem.fromMap).toList();
  }

  static Future<void> saveCart(List<CartItem> cart) async {
    await _box.put('ewn_cart', jsonEncode(cart.map((c) => c.toMap()).toList()));
  }

  // ---------------- B) Likes ----------------

  static List<String> loadLikes() {
    final raw = _box.get('ewn_likes');
    if (raw == null) return [];
    return (jsonDecode(raw as String) as List).cast<String>();
  }

  static Future<void> saveLikes(List<String> likes) async {
    await _box.put('ewn_likes', jsonEncode(likes));
  }

  // ---------------- B) Orders ----------------

  static List<Map<String, dynamic>> loadOrders() {
    final raw = _box.get('ewn_orders');
    if (raw == null) return [];
    return (jsonDecode(raw as String) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> saveOrders(List<Map<String, dynamic>> orders) async {
    await _box.put('ewn_orders', jsonEncode(orders));
  }

  // ---------------- B) Products offline fallback cache ----------------
  // Deliberately has NO expiry timestamp check — mirrors PRODUCTS_CACHE_KEY
  // in main-render.js, which is only ever read when the network fetch /
  // Firestore stream both fail (true offline), never as a "still fresh
  // enough" shortcut while online.

  static Future<void> cacheProducts(List<Product> products) async {
    await _box.put(
      'ewn_products_cache',
      jsonEncode(products.map((p) => p.toCacheMap()).toList()),
    );
  }

  static List<Product> loadCachedProducts() {
    final raw = _box.get('ewn_products_cache');
    if (raw == null) return [];
    final list = (jsonDecode(raw as String) as List).cast<Map<String, dynamic>>();
    return list.map((m) => Product.fromMap(m['id'] as String, m)).toList();
  }

  // ---------------- B) Device ID (referral fraud guard, main-coins.js) ----------------

  static String getOrCreateDeviceId() {
    var id = _box.get('ewn_device_id') as String?;
    if (id == null) {
      id = 'dvc-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
      _box.put('ewn_device_id', id);
    }
    return id;
  }

  // ---------------- Misc small prefs (lang/theme/location) ----------------

  static String? getString(String key) => _box.get(key) as String?;
  static Future<void> setString(String key, String value) => _box.put(key, value);
  static Future<void> remove(String key) => _box.delete(key);
}
