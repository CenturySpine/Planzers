#!/usr/bin/env bash
set -euo pipefail

./flutter_sdk/bin/flutter pub get

if [ "${VERCEL_ENV:-}" = "production" ]; then
  ./flutter_sdk/bin/flutter build web -t lib/main_prod.dart --release --dart-define=FIREBASE_VAPID_KEY="${FIREBASE_VAPID_KEY_PROD:-}"
else
  ./flutter_sdk/bin/flutter build web -t lib/main_preview.dart --release --dart-define=FIREBASE_VAPID_KEY="${FIREBASE_VAPID_KEY_PREVIEW:-}"
fi
