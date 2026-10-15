#!/bin/zsh
# Draws the app icon and the README's duck line-up from the duck's pixel art (QuackieChan/Duck/Sprites.swift).
set -euo pipefail
cd "$(dirname "$0")/.."

ICONS=QuackieChan/Assets.xcassets/AppIcon.appiconset
mkdir -p "$ICONS"
[[ -f QuackieChan/Assets.xcassets/Contents.json ]] ||
  echo '{ "info" : { "author" : "xcode", "version" : 1 } }' > QuackieChan/Assets.xcassets/Contents.json

BUILD=$(mktemp -d)
swiftc -O -parse-as-library -module-name AppIcon -o "$BUILD/appicon" \
  QuackieChan/Duck/Sprites.swift scripts/icon/AppIcon.swift
"$BUILD/appicon" "$ICONS" docs/images
rm -rf "$BUILD"
echo "Icons written to $ICONS and docs/images"
