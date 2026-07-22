#!/usr/bin/env bash
# Idempotent — safe to run every build. Only makes a change if the
# google-services plugin isn't already wired (newer firebase_core
# versions sometimes auto-wire this; this script is the fallback for
# when they don't).
#
# Handles BOTH Gradle file formats, because `flutter create` defaults
# to Kotlin DSL (build.gradle.kts / settings.gradle.kts) since Flutter
# 3.29 — before that it generated Groovy (build.gradle / settings.gradle).
# Since codemagic.yaml now tracks `flutter: stable`, whichever format
# the currently-installed stable SDK scaffolds is auto-detected here.
set -e

if [ -f "android/settings.gradle.kts" ]; then
  SETTINGS="android/settings.gradle.kts"
  IS_KTS=true
else
  SETTINGS="android/settings.gradle"
  IS_KTS=false
fi

if [ -f "android/app/build.gradle.kts" ]; then
  APP_BUILD="android/app/build.gradle.kts"
else
  APP_BUILD="android/app/build.gradle"
fi

echo "Checking Firebase Gradle wiring (settings=$SETTINGS, app=$APP_BUILD, kts=$IS_KTS)..."

# 1) Declare the google-services plugin in settings.gradle(.kts)'s
#    pluginManagement { plugins { ... } } block.
if [ -f "$SETTINGS" ] && ! grep -q "com.google.gms.google-services" "$SETTINGS"; then
  if [ "$IS_KTS" = true ]; then
    # Kotlin DSL: id("com.android.application") version "..." apply false
    sed -i.bak '/id("com.android.application") version/a\
    id("com.google.gms.google-services") version "4.4.2" apply false' "$SETTINGS"
  else
    # Groovy: id "com.android.application" version "..." apply false
    sed -i.bak '/id "com.android.application" version/a\
    id "com.google.gms.google-services" version "4.4.2" apply false' "$SETTINGS"
  fi
  echo "✅ Added google-services plugin declaration to $SETTINGS"
else
  echo "$SETTINGS already wired (or not found) — skipping."
fi

# 2) Apply the plugin in app/build.gradle(.kts)'s plugins { } block.
if [ -f "$APP_BUILD" ] && ! grep -q "com.google.gms.google-services" "$APP_BUILD"; then
  if [[ "$APP_BUILD" == *.kts ]]; then
    # Kotlin DSL: id("dev.flutter.flutter-gradle-plugin")
    sed -i.bak '/id("dev.flutter.flutter-gradle-plugin")/a\
    id("com.google.gms.google-services")' "$APP_BUILD"
  else
    # Groovy: id "dev.flutter.flutter-gradle-plugin"
    sed -i.bak '/id "dev.flutter.flutter-gradle-plugin"/a\
    id "com.google.gms.google-services"' "$APP_BUILD"
  fi
  echo "✅ Applied google-services plugin in $APP_BUILD"
else
  echo "$APP_BUILD already wired (or not found) — skipping."
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
