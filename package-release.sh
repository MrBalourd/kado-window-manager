#!/bin/sh
set -eu

cd "$(dirname "$0")"

./build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Kado.app/Contents/Info.plist)"
ARCH="$(uname -m)"
RELEASE_DIR="$PWD/release"
KADO_TMPDIR="$(mktemp -d /tmp/kado-release.XXXXXX)"
trap 'rm -rf "$KADO_TMPDIR"' EXIT HUP INT TERM
STAGED_APP="$KADO_TMPDIR/Kado.app"
OUTPUT_ZIP="$RELEASE_DIR/Kado-$VERSION-macos-$ARCH.zip"

mkdir -p "$RELEASE_DIR"
ditto Kado.app "$STAGED_APP"
xattr -cr "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$OUTPUT_ZIP"
unzip -t "$OUTPUT_ZIP" >/dev/null

printf 'Created GitHub release asset: %s\n' "$OUTPUT_ZIP"
