#!/usr/bin/env bash
# Idempotent — safe to run every build. Only makes a change if the
# google-services plugin isn't already wired (newer firebase_core
# versions sometimes auto-wire this; this script is the fallback for
# when they don't).
set -e

SETTINGS="android/settings.gradle"
APP_BUILD="android/app/build.gradle"

echo "Checking Firebase Gradle wiring..."

# 1) Declare the google-services plugin in settings.gradle (modern
#    Flutter template's pluginManagement { plugins { ... } } block).
if [ -f "$SETTINGS" ] && ! grep -q "com.google.gms.google-services" "$SETTINGS"; then
  sed -i.bak '/id "com.android.application" version/a\
    id "com.google.gms.google-services" version "4.4.2" apply false' "$SETTINGS"
  echo "✅ Added google-services plugin declaration to settings.gradle"
else
  echo "settings.gradle already wired (or not found) — skipping."
fi

# 2) Apply the plugin in app/build.gradle's plugins { } block.
if [ -f "$APP_BUILD" ] && ! grep -q "com.google.gms.google-services" "$APP_BUILD"; then
  sed -i.bak '/id "dev.flutter.flutter-gradle-plugin"/a\
    id "com.google.gms.google-services"' "$APP_BUILD"
  echo "✅ Applied google-services plugin in app/build.gradle"
else
  echo "app/build.gradle already wired (or not found) — skipping."
fi

# 3) firebase_messaging / image_picker need minSdk 23+.
if [ -f "$APP_BUILD" ]; then
  sed -i.bak \
    -e 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/' \
    -e 's/minSdk = flutter.minSdkVersion/minSdk = 23/' \
    -e 's/minSdk flutter.minSdkVersion/minSdk 23/' \
    "$APP_BUILD" || true
  echo "✅ minSdkVersion set to 23"
fi

# 4) applicationId must match the package_name inside google-services.json.
if [ -f "android/app/google-services.json" ] && [ -f "$APP_BUILD" ]; then
  PKG=$(grep -o '"package_name": *"[^"]*"' android/app/google-services.json | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  if [ -n "$PKG" ] && ! grep -q "applicationId \"$PKG\"" "$APP_BUILD" && ! grep -q "applicationId = \"$PKG\"" "$APP_BUILD"; then
    sed -i.bak \
      -e "s/applicationId \"com.example.ewn_hlm\"/applicationId \"$PKG\"/" \
      -e "s/applicationId = \"com.example.ewn_hlm\"/applicationId = \"$PKG\"/" \
      "$APP_BUILD" || true
    echo "✅ applicationId aligned with google-services.json ($PKG)"
  fi
fi

rm -f "$SETTINGS.bak" "$APP_BUILD.bak" 2>/dev/null || true
echo "Done."
