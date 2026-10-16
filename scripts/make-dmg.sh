#!/bin/zsh
# Builds Quackie Chan and packs it into build/QuackieChan.dmg: the app next to a shortcut to Applications,
# so you can drag it across. That's the file to attach to a GitHub release; install.sh downloads it from there.
# Pass --skip-build to pack the app already in build/.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "${1:-}" == "--skip-build" ]] || ./scripts/build.sh

APP="build/Quackie Chan.app"
[[ -d "$APP" ]] || { echo "No app at $APP. Run scripts/build.sh first."; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Quackie Chan.app"
ln -s /Applications "$STAGE/Applications"

DMG=build/QuackieChan.dmg
rm -f "$DMG"
hdiutil create -volname "Quackie Chan" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
