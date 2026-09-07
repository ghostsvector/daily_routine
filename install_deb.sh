#!/bin/bash
# Downloads the latest (or a specified) Daily Routine release .deb straight
# from GitHub Releases, verifies its checksum and GPG signature, and
# installs it. This is the "just get the app running" path — no local
# build, no cloning the SDK, no Flutter toolchain needed. To build from
# this checkout's source instead, use build_deb.sh.
#
# Usage:
#   ./install_deb.sh          # latest release
#   ./install_deb.sh v1.2.7   # a specific tag
set -euo pipefail

REPO="kasinadhsarma/daily_routine"
ARCH="amd64"
VERSION="${1:-}"

echo "==> Checking dependencies"
command -v curl >/dev/null || { echo "Error: curl not found" >&2; exit 1; }
command -v gpg >/dev/null || { echo "Error: gpg not found (sudo apt install gnupg)" >&2; exit 1; }
command -v dpkg >/dev/null || { echo "Error: dpkg not found" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "Error: sha256sum not found" >&2; exit 1; }

if [[ -z "$VERSION" ]]; then
    echo "==> Looking up the latest release"
    # Captured into a variable rather than piped straight into grep -m1 —
    # grep -m1 closes its input as soon as it finds a match, and curl then
    # errors ("Failure writing output to destination") trying to write to
    # the now-closed pipe. Capturing first lets curl finish cleanly.
    API_RESPONSE="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")"
    VERSION="$(printf '%s' "$API_RESPONSE" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
    if [[ -z "$VERSION" ]]; then
        echo "Error: couldn't determine the latest release tag" >&2
        exit 1
    fi
fi
VERSION_NUM="${VERSION#v}"
BASE_URL="https://github.com/$REPO/releases/download/$VERSION"
DEB_FILE="daily-routine-${VERSION_NUM}_${ARCH}.deb"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

echo "==> Downloading $VERSION"
curl -fsSL -O "$BASE_URL/$DEB_FILE"
curl -fsSL -O "$BASE_URL/$DEB_FILE.asc"
curl -fsSL -O "$BASE_URL/SHA256SUMS"
curl -fsSL -O "$BASE_URL/SHA256SUMS.asc"

echo "==> Verifying checksum"
sha256sum --ignore-missing -c SHA256SUMS

echo "==> Verifying GPG signature"
# Fetched fresh from the repo rather than assumed to be alongside this
# script, so this still works if the script is copied/run standalone.
curl -fsSL -o release-signing-key.asc \
    "https://raw.githubusercontent.com/$REPO/main/release-signing-key.asc"
gpg --import release-signing-key.asc 2>/dev/null
gpg --verify SHA256SUMS.asc SHA256SUMS
gpg --verify "$DEB_FILE.asc" "$DEB_FILE"

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

echo "==> Installed $VERSION successfully. Launch with: daily-routine"
