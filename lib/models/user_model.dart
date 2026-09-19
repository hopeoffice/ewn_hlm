// The web app does NOT use Firebase Auth — it stores name/phone/pin
// directly under users/{phone} in Realtime Database and checks the PIN
// client-side against that record (see loginWithUserData() main-config.js).
// We keep that exact scheme here so the same `users/` tree in Firebase
// works unmodified for both the PWA and this Flutter app.
class UserModel {
  final String name;
  final String phone;
  // 'basic' (phone+name only, no coin/wallet access) or 'wallet' (email +
  // password set, emailVerified === true, full coin access). Defaults to
  // 'wallet' for any session persisted before this field existed — every
  // account that predates the basic tier already has email+password.
  final String tier;
  // False only for a freshly-entered phone number with no users/{phone}
  // record on the server yet (see AppState.enterBasicLocal() /
  // _ensureBasicAccountExists()) — lets a mistyped phone number that
  // nobody ever orders from or activates a wallet with stay purely
  // local and never touch the database. True for every other session
  // (including sessions saved before this field existed).
  final bool hasServerAccount;

  UserModel({required this.name, required this.phone, this.tier = 'wallet', this.hasServerAccount = true});

  factory UserModel.fromMap(Map<String, dynamic> m) => UserModel(
        name: m['name'] as String,
        phone: m['phone'] as String,
        tier: (m['tier'] as String?) ?? 'wallet',
        hasServerAccount: (m['hasServerAccount'] as bool?) ?? true,
      );

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone, 'tier': tier, 'hasServerAccount': hasServerAccount};
}
