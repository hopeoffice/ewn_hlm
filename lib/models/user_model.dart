// The web app does NOT use Firebase Auth — it stores name/phone/pin
// directly under users/{phone} in Realtime Database and checks the PIN
// client-side against that record (see loginWithUserData() main-config.js).
// We keep that exact scheme here so the same `users/` tree in Firebase
// works unmodified for both the PWA and this Flutter app.
class UserModel {
  final String name;
  final String phone;

  UserModel({required this.name, required this.phone});

  factory UserModel.fromMap(Map<String, dynamic> m) =>
      UserModel(name: m['name'] as String, phone: m['phone'] as String);

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};
}
