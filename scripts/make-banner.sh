#!/bin/zsh
# Draws docs/images/banner.png (1600 × 400) from the duck's pixel art (QuackieChan/Duck/Sprites.swift).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=$(mktemp -d)
swiftc -O -parse-as-library -module-name Banner -o "$BUILD/banner" \
  QuackieChan/Duck/Sprites.swift scripts/banner/Banner.swift
"$BUILD/banner" QuackieChan/Fonts/Fredoka.ttf docs/images/banner.png
rm -rf "$BUILD"
echo "Banner written to docs/images/banner.png"
