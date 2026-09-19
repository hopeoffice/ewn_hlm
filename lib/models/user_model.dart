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

  UserModel({required this.name, required this.phone, this.tier = 'wallet'});

  factory UserModel.fromMap(Map<String, dynamic> m) => UserModel(
        name: m['name'] as String,
        phone: m['phone'] as String,
        tier: (m['tier'] as String?) ?? 'wallet',
      );

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone, 'tier': tier};
}
