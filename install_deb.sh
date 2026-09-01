#!/bin/bash
# Build the Flutter Linux app from scratch and install it as a .deb package.
set -euo pipefail

APP_NAME="daily-routine"
BIN_NAME="daily_routine"
APP_DISPLAY_NAME="Daily Routine"
ARCH="amd64"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(grep -m1 '^version:' "$PROJECT_DIR/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)"

BUNDLE_DIR="$PROJECT_DIR/build/linux/x64/release/bundle"
DIST_DIR="$PROJECT_DIR/dist"
PKG_ROOT="$(mktemp -d)"
trap 'rm -rf "$PKG_ROOT"' EXIT

echo "==> Checking dependencies"
command -v flutter >/dev/null || { echo "Error: flutter not found in PATH" >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo "Error: dpkg-deb not found (sudo apt install dpkg-dev)" >&2; exit 1; }

echo "==> Fetching packages"
flutter pub get

echo "==> Building Linux release bundle"
flutter build linux --release

if [[ ! -f "$BUNDLE_DIR/$BIN_NAME" ]]; then
    echo "Error: build did not produce $BUNDLE_DIR/$BIN_NAME" >&2
    exit 1
fi

echo "==> Assembling package tree"
INSTALL_LIB_DIR="$PKG_ROOT/opt/$APP_NAME"
mkdir -p "$INSTALL_LIB_DIR"
cp -r "$BUNDLE_DIR"/. "$INSTALL_LIB_DIR/"

mkdir -p "$PKG_ROOT/usr/bin"
ln -sf "/opt/$APP_NAME/$BIN_NAME" "$PKG_ROOT/usr/bin/$APP_NAME"

mkdir -p "$PKG_ROOT/usr/share/applications"
cat > "$PKG_ROOT/usr/share/applications/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_DISPLAY_NAME
Exec=/opt/$APP_NAME/$BIN_NAME
Icon=$APP_NAME
Terminal=false
Categories=Utility;
EOF

mkdir -p "$PKG_ROOT/usr/share/icons/hicolor/512x512/apps"
ICON_SRC="$PROJECT_DIR/web/icons/Icon-512.png"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$PKG_ROOT/usr/share/icons/hicolor/512x512/apps/$APP_NAME.png"
fi

mkdir -p "$PKG_ROOT/DEBIAN"
INSTALLED_SIZE="$(du -sk "$PKG_ROOT" | cut -f1)"
cat > "$PKG_ROOT/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Installed-Size: $INSTALLED_SIZE
Maintainer: Kasinadh Sarma <kasinadhsarma@gmail.com>
Description: $APP_DISPLAY_NAME
 A Flutter-based daily routine and task management app.
EOF

echo "==> Building .deb package"
mkdir -p "$DIST_DIR"
DEB_FILE="$DIST_DIR/${APP_NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$PKG_ROOT" "$DEB_FILE"

echo "==> Installing $DEB_FILE"
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

if ! $SUDO dpkg -i "$DEB_FILE"; then
    echo "Resolving missing dependencies ..."
    $SUDO apt-get install -f -y
fi

echo "==> Installed successfully. Launch with: $APP_NAME"
