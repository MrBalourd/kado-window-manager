#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift Scripts/generate-app-icon.swift
iconutil -c icns Resources/Kado.iconset -o Resources/Kado.icns
swift build -c release
APP="$PWD/Kado.app"
SIGNING_IDENTITY="${KADO_SIGNING_IDENTITY:--}"
if [ "$SIGNING_IDENTITY" != "-" ] && ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
  echo 'The requested signing identity was not found. Check KADO_SIGNING_IDENTITY.' >&2
  exit 1
fi

KADO_BUILD_TMPDIR="$(mktemp -d /tmp/kado-build.XXXXXX)"
trap 'rm -rf "$KADO_BUILD_TMPDIR"' EXIT HUP INT TERM
STAGED_APP="$KADO_BUILD_TMPDIR/Kado.app"
mkdir -p "$STAGED_APP/Contents/MacOS"
cp .build/release/Kado "$STAGED_APP/Contents/MacOS/Kado"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
mkdir -p "$STAGED_APP/Contents/Resources"
cp Resources/Kado.icns "$STAGED_APP/Contents/Resources/Kado.icns"
xattr -rc "$STAGED_APP"
codesign --force --sign "$SIGNING_IDENTITY" "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"

rm -rf "$APP"
ditto "$STAGED_APP" "$APP"
xattr -rc "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
if ! codesign --verify --deep --strict "$APP" 2>/dev/null; then
  verification_directory="$(mktemp -d /tmp/kado-signature-check.XXXXXX)"
  ditto "$APP" "$verification_directory/Kado.app"
  xattr -cr "$verification_directory/Kado.app"
  xattr -d com.apple.FinderInfo "$verification_directory/Kado.app" 2>/dev/null || true
  codesign --verify --deep --strict "$verification_directory/Kado.app"
  echo "The signed app verifies from a clean copy; the synced output folder adds Finder metadata to the bundle."
fi
printf 'Built %s\n' "$APP"
