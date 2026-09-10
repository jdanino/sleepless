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
#
# Run `./release.sh --check` first: it says what is missing and changes nothing.
#      It asks for an app-specific password. Make one at appleid.apple.com.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/build/Sleepless.app"
PROFILE="${NOTARY_PROFILE:-sleepless}"
TEAM_ID="${APPLE_TEAM_ID:-25GE53E3A4}"

IDENTITY="$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"

have_credential() { xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; }

# `./release.sh --check` reports what is missing and changes nothing.
if [ "${1:-}" = "--check" ]; then
  status=0
  if [ -n "$IDENTITY" ]; then
    echo "OK   certificate: $IDENTITY"
  else
    echo "MISS certificate: no 'Developer ID Application' in the keychain."
    echo "     Xcode > Settings > Accounts > <your account> > Manage Certificates"
    echo "     > '+' > Developer ID Application."
    status=1
  fi
  if have_credential; then
    echo "OK   notarisation credential '$PROFILE'"
  else
    echo "MISS notarisation credential '$PROFILE'."
    echo "     xcrun notarytool store-credentials $PROFILE \\"
    echo "       --apple-id <your Apple ID> --team-id $TEAM_ID"
    status=1
  fi
  [ "$status" = 0 ] && echo && echo "Everything is ready. Run ./release.sh"
  exit "$status"
fi

if [ -z "$IDENTITY" ]; then
  echo "No Developer ID Application certificate found. Run ./release.sh --check"
  exit 1
fi
echo "Signing identity: $IDENTITY"

# 1. Build, but do not install.
"$HERE/build.sh" -

# The version comes from the bundle that was just built. Read it only now:
# PlistBuddy writes its error to stdout, so on a missing file it would put a
# whole error message into the name of the DMG.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$HERE/build/Sleepless-$VERSION.dmg"
echo "Version: $VERSION"

# 2. Sign with the hardened runtime. Notarisation demands it.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"


if ! have_credential; then
  echo "No notarytool credential named '$PROFILE'. Run ./release.sh --check"
  exit 1
fi

# 3. Notarise the app FIRST and staple the ticket to it.
#
#    Order matters. The ticket must be inside the app before the app goes into
#    the DMG. A ticket on the DMG alone disappears the moment the user drags
#    the app to Applications: Gatekeeper must then ask Apple over the network,
#    and a first start with no network fails.
ZIP="$HERE/build/Sleepless-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

# 4. Make the DMG around the stapled app.
rm -rf "$HERE/build/dmg" "$DMG"
mkdir -p "$HERE/build/dmg"
cp -R "$APP" "$HERE/build/dmg/"
ln -s /Applications "$HERE/build/dmg/Applications"
hdiutil create -volname "Sleepless" -srcfolder "$HERE/build/dmg" \
  -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# 5. Notarise the DMG itself. Gatekeeper judges a disk image on its own, so
#    without this the app is good while opening the DMG still warns.
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo
echo "Ready: $DMG"
echo "Check it as a new user does:  spctl -a -t open --context context:primary-signature -v '$DMG'"
