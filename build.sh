#!/bin/bash
# Builds Sleepless.app and installs it in ~/Applications.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/build/Sleepless.app"
DEST="${1:-$HOME/Applications}"   # Give "-" to build only, with no install.

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Sleepless</string>
  <key>CFBundleDisplayName</key><string>Sleepless</string>
  <key>CFBundleIdentifier</key><string>nl.danino.sleepless</string>
  <key>CFBundleExecutable</key><string>Sleepless</string>
  <key>CFBundleIconFile</key><string>Sleepless</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Sleepless</string>
</dict>
</plist>
PLIST

# Builds for both architectures and joins them, so Intel Macs also work.
for ARCH in arm64 x86_64; do
  swiftc -O \
    -target "$ARCH-apple-macos13.0" \
    -o "$HERE/build/Sleepless-$ARCH" \
    "$HERE/src/Icon.swift" "$HERE/src/main.swift"
done
lipo -create -output "$APP/Contents/MacOS/Sleepless" \
  "$HERE/build/Sleepless-arm64" "$HERE/build/Sleepless-x86_64"

# Makes the Finder icon from the same drawing code.
ICONTOOL="$HERE/build/icontool"
swiftc -O -target arm64-apple-macos13.0 -o "$ICONTOOL" "$HERE/src/Icon.swift" "$HERE/tools/main.swift"
"$ICONTOOL" iconset "$HERE/build/Sleepless.iconset" >/dev/null
iconutil -c icns "$HERE/build/Sleepless.iconset" -o "$APP/Contents/Resources/Sleepless.icns"

codesign --force --deep --sign - "$APP"

if [ "$DEST" = "-" ]; then
  echo "Built: $APP"
else
  mkdir -p "$DEST"
  rm -rf "$DEST/Sleepless.app"
  cp -R "$APP" "$DEST/Sleepless.app"
  echo "Installed: $DEST/Sleepless.app"
fi
