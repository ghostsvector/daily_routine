#!/usr/bin/env bash
# Interactive flavor picker for `flutter run`.
# Usage: ./run.sh [extra flutter run args...]
set -euo pipefail

echo "Select flavor:"
echo "[1]: internal"
echo "[2]: external"
read -rp "Please choose one (or \"q\" to quit): " choice

case "$choice" in
  1) flavor="internal" ;;
  2) flavor="external" ;;
  q|Q) exit 0 ;;
  *) echo "Invalid choice: $choice" >&2; exit 1 ;;
esac

if [[ ! -f .env && ! -f .env.local ]]; then
  echo "Missing .env (or .env.local) — copy .env.example to .env and fill in your Firebase project's values, or run \`flutterfire configure\`." >&2
  exit 1
fi

echo
echo "Select device:"
echo "[1]: Linux desktop"
echo "[2]: let flutter choose (prompts if more than one device is attached)"
read -rp "Please choose one (or \"q\" to quit): " device_choice

device_args=()
case "$device_choice" in
  1) device_args=(-d linux) ;;
  2) ;;
  q|Q) exit 0 ;;
  *) echo "Invalid choice: $device_choice" >&2; exit 1 ;;
esac

echo "Launching lib/main.dart with FLAVOR=$flavor..."
# FLAVOR picks which lib/flavors/<flavor>/firebase_options.dart is used
# (see lib/flavors/flavor_selector.dart). There's no Android Gradle product
# flavor defined for this app, so --flavor is intentionally not passed.
#
# Firebase credentials themselves come from .env/.env.local (loaded at
# runtime via flutter_dotenv, bundled as assets — see pubspec.yaml), not
# from a --dart-define-from-file secrets file.
exec flutter run --dart-define=FLAVOR="$flavor" "${device_args[@]}" "$@"
