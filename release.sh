#!/bin/bash
# Makes a signed, notarised DMG of Sleepless for other Macs.
#
# It needs two things one time only:
#   1. A "Developer ID Application" certificate in your keychain.
#      Xcode > Settings > Accounts > your account > Manage Certificates
#      > "+" > Developer ID Application.
#   2. A notarytool credential:
#      xcrun notarytool store-credentials sleepless \
#        --apple-id <your Apple ID> --team-id 25GE53E3A4
#      It asks for an app-specific password. Make one at appleid.apple.com.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/build/Sleepless.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="$HERE/build/Sleepless-$VERSION.dmg"
PROFILE="${NOTARY_PROFILE:-sleepless}"

IDENTITY="$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application certificate found."
  echo "Make one in Xcode > Settings > Accounts > Manage Certificates, then run this again."
  exit 1
fi
echo "Signing identity: $IDENTITY"

# 1. Build, but do not install.
"$HERE/build.sh" -

# 2. Sign with the hardened runtime. Notarisation demands it.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo
echo "TEST NOW, BEFORE YOU CONTINUE:"
echo "  open '$APP', then toggle one time."
echo "  The hardened runtime can stop 'do shell script with administrator privileges'."
echo "  If the toggle fails, the app needs a privileged helper instead."
read -r -p "Did the toggle work? [y/N] " answer
[ "$answer" = "y" ] || { echo "Stopped."; exit 1; }

# 3. Make the DMG.
rm -rf "$HERE/build/dmg" "$DMG"
mkdir -p "$HERE/build/dmg"
cp -R "$APP" "$HERE/build/dmg/"
ln -s /Applications "$HERE/build/dmg/Applications"
hdiutil create -volname "Sleepless" -srcfolder "$HERE/build/dmg" \
  -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# 4. Notarise and staple.
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "No notarytool credential named '$PROFILE'. See the top of this file."
  echo "The DMG is signed but not notarised: $DMG"
  exit 1
fi
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo
echo "Ready: $DMG"
echo "Check it as a new user does:  spctl -a -t open --context context:primary-signature -v '$DMG'"
