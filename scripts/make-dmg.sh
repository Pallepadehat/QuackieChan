#!/bin/zsh
# Builds Quackie Chan and packs it into build/QuackieChan.dmg: the app next to a shortcut to Applications, so you
# can drag it across. That's the file a GitHub release carries; install.sh downloads it from there.
#
#   --notarize     sign with Developer ID, have Apple notarize it and staple the ticket, so macOS opens it without
#                  "Apple couldn't check it for malware", even when downloaded in a browser. Needs a one-time
#                  `xcrun notarytool store-credentials quackie-notary` (see the README, "Making a release").
#   --skip-build   pack the app already in build/
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=0 BUILD=1
for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=1 ;;
    --skip-build) BUILD=0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done
PROFILE=${QUACKIE_NOTARY_PROFILE:-quackie-notary}

if (( NOTARIZE )); then
  # Fail early, before a long build, if notarytool can't log in, and say why.
  if ! CHECK=$(xcrun notarytool history --keychain-profile "$PROFILE" 2>&1); then
    if [[ "$CHECK" == *"No Keychain password item"* ]]; then
      echo "notarytool has no saved login called \"$PROFILE\". Set it up once with:"
      echo "  xcrun notarytool store-credentials $PROFILE --apple-id <your Apple ID> --team-id 537P4FPMZ4"
    elif [[ "$CHECK" == *"agreement"* ]]; then
      echo "Apple needs you to accept the latest Apple Developer Program License Agreement first:"
      echo "  https://developer.apple.com/account (sign in and accept the banner at the top)"
    else
      echo "notarytool couldn't log in: $CHECK"
    fi
    exit 1
  fi
fi
(( BUILD )) && { (( NOTARIZE )) && QUACKIE_SIGN=developer-id ./scripts/build.sh || ./scripts/build.sh; }

APP="build/Quackie Chan.app"
[[ -d "$APP" ]] || { echo "No app at $APP. Run scripts/build.sh first."; exit 1; }
if (( NOTARIZE )); then
  codesign -dv "$APP" 2>&1 | grep -q "Authority=Developer ID Application" \
    || { echo "$APP isn't signed with Developer ID. Build it with --notarize (without --skip-build)."; exit 1; }
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Quackie Chan.app"
ln -s /Applications "$STAGE/Applications"

DMG=build/QuackieChan.dmg
rm -f "$DMG"
hdiutil create -volname "Quackie Chan" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet

if (( NOTARIZE )); then
  codesign --sign "Developer ID Application" --timestamp "$DMG"
  echo "Sending it to Apple to be notarized (usually a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | tee build/notarize.log
  grep -q "status: Accepted" build/notarize.log || {
    echo "Apple didn't accept it. Ask why with: xcrun notarytool log <submission id> --keychain-profile $PROFILE"
    exit 1
  }
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
