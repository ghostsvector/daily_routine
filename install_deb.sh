#!/bin/bash
set -euo pipefail

APP_NAME="daily-routine"
DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dist"

# Allow overriding the .deb path as the first argument, otherwise pick the
# newest matching package in dist/.
DEB_FILE="${1:-}"
if [[ -z "$DEB_FILE" ]]; then
    DEB_FILE="$(find "$DIST_DIR" -maxdepth 1 -name "${APP_NAME}_*.deb" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -n1 | cut -d' ' -f2- || true)"
fi

if [[ -z "$DEB_FILE" || ! -f "$DEB_FILE" ]]; then
    echo "Error: no .deb package found. Build one first (e.g. flutter build linux) or pass a path." >&2
    exit 1
fi

echo "Installing $DEB_FILE ..."

if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

if ! $SUDO dpkg -i "$DEB_FILE"; then
    echo "Resolving missing dependencies ..."
    $SUDO apt-get install -f -y
fi

echo "Installed successfully. Launch with: $APP_NAME"
