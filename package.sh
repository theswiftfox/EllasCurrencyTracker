#!/usr/bin/env bash
#
# package.sh - Build a distributable zip for EllasCurrencyTracker
#
# Downloads the required Ace3 libraries, bundles them into Libs/,
# and produces a ready-to-install zip file.
#
# Usage:  ./package.sh
# Output: EllasCurrencyTracker-<version>.zip

set -euo pipefail

ADDON_NAME="EllasCurrencyTracker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$(mktemp -d)"
ACE3_REPO="https://github.com/WoWUIDev/Ace3.git"

# Read version from TOC
VERSION=$(grep -m1 '## Version:' "$SCRIPT_DIR/${ADDON_NAME}.toc" | sed 's/## Version: *//')
VERSION="${VERSION:-dev}"
ZIPNAME="${ADDON_NAME}-${VERSION}.zip"

# Parse library list from .pkgmeta externals (single source of truth)
REQUIRED_LIBS=()
while IFS= read -r line; do
    # Match "  Libs/<name>:" directory lines
    if [[ "$line" =~ ^[[:space:]]+Libs/([^:]+): ]]; then
        REQUIRED_LIBS+=("${BASH_REMATCH[1]}")
    fi
done < "$SCRIPT_DIR/.pkgmeta"

if [ ${#REQUIRED_LIBS[@]} -eq 0 ]; then
    echo "ERROR: No externals found in .pkgmeta" >&2
    exit 1
fi

echo "==> Building ${ADDON_NAME} v${VERSION}"

# ---------- Fetch Ace3 libraries ----------
echo "==> Fetching Ace3 libraries..."
ACE3_DIR="${BUILD_DIR}/Ace3"
git clone --depth 1 --quiet "$ACE3_REPO" "$ACE3_DIR"

# ---------- Assemble addon folder ----------
DEST="${BUILD_DIR}/${ADDON_NAME}"
mkdir -p "${DEST}/Libs"

# Copy addon files (exclude dev/build artifacts)
for f in *.toc *.lua *.xml LICENSE.md preview.png; do
    [ -f "$SCRIPT_DIR/$f" ] && cp "$SCRIPT_DIR/$f" "$DEST/"
done

# Copy required libraries
for lib in "${REQUIRED_LIBS[@]}"; do
    if [ -d "$ACE3_DIR/$lib" ]; then
        cp -r "$ACE3_DIR/$lib" "$DEST/Libs/"
    else
        echo "WARNING: Library $lib not found in Ace3 repo" >&2
    fi
done

# ---------- Create zip ----------
echo "==> Creating ${ZIPNAME}..."
(cd "$BUILD_DIR" && zip -r -q "$SCRIPT_DIR/$ZIPNAME" "$ADDON_NAME")

# ---------- Cleanup ----------
rm -rf "$BUILD_DIR"

echo "==> Done: ${ZIPNAME} ($(du -h "$SCRIPT_DIR/$ZIPNAME" | cut -f1))"
