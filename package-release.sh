#!/bin/sh
set -eu

cd "$(dirname "$0")"

./build-app.sh

swift build -c release --triple arm64-apple-macosx14.0 -Xswiftc -gnone
swift build -c release --triple x86_64-apple-macosx14.0 -Xswiftc -gnone

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Kado.app/Contents/Info.plist)"
RELEASE_DIR="$PWD/release"
KADO_TMPDIR="$(mktemp -d /tmp/kado-release.XXXXXX)"
trap 'rm -rf "$KADO_TMPDIR"' EXIT HUP INT TERM
STAGED_APP="$KADO_TMPDIR/Kado.app"
OUTPUT_ZIP="$RELEASE_DIR/Kado-$VERSION-macos-universal.zip"

mkdir -p "$RELEASE_DIR"
ditto Kado.app "$STAGED_APP"
xattr -cr "$STAGED_APP"
lipo -create \
  .build/arm64-apple-macosx/release/Kado \
  .build/x86_64-apple-macosx/release/Kado \
  -output "$STAGED_APP/Contents/MacOS/Kado"
SIGNING_IDENTITY="${KADO_SIGNING_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$OUTPUT_ZIP"
unzip -t "$OUTPUT_ZIP" >/dev/null

printf 'Created GitHub release asset: %s\n' "$OUTPUT_ZIP"
