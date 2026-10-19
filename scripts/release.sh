#!/bin/zsh
# Makes a release: builds a notarized QuackieChan.dmg and publishes it as a GitHub release, where install.sh finds
# it, along with appcast.xml, where the app itself finds it (Sparkle). The version comes from MARKETING_VERSION in
# project.yml.
#
# The appcast is signed with the Sparkle key in your keychain (made once with Sparkle's generate_keys; its public
# half is SUPublicEDKey in project.yml). Keep a backup of it: `generate_keys -x sparkle-key.txt` exports it. Without
# it, apps already out there can't update.
#
#   ./scripts/release.sh                       signed with Developer ID and notarized by Apple
#   ./scripts/release.sh --without-notarizing  signed with Developer ID only, while the developer membership is off
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"(.*)".*/\1/')
TAG="v$VERSION"
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first, so the release matches the code."; exit 1; }
git fetch --tags --quiet
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "$TAG already exists. Bump MARKETING_VERSION in project.yml first."
  exit 1
fi

NOTES=()
if [[ "${1:-}" == "--without-notarizing" ]]; then
  ./scripts/make-dmg.sh --sign
  NOTES=(--notes "Not notarized by Apple yet. Install it with the one-liner in the README, which handles that, or see the README for opening the .dmg the first time.")
else
  ./scripts/make-dmg.sh --notarize
  NOTES=(--generate-notes)
fi

# The appcast: one entry for this version, signed with our EdDSA key, pointing at this release's disk image.
GENERATE_APPCAST=$(find build/DerivedData/SourcePackages/artifacts -name generate_appcast -type f -perm -u+x | head -1)
[[ -n "$GENERATE_APPCAST" ]] || { echo "Couldn't find Sparkle's generate_appcast. Build once so Swift packages are fetched."; exit 1; }
rm -rf build/appcast
mkdir -p build/appcast
cp build/QuackieChan.dmg build/appcast/
"$GENERATE_APPCAST" --download-url-prefix "https://github.com/Pallepadehat/QuackieChan/releases/download/$TAG/" \
  --link "https://github.com/Pallepadehat/QuackieChan/releases/tag/$TAG" --maximum-versions 1 build/appcast
[[ -f build/appcast/appcast.xml ]] || { echo "No appcast was made."; exit 1; }

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" build/QuackieChan.dmg build/appcast/appcast.xml --title "Quackie Chan $VERSION" "${NOTES[@]}"
echo "Released $TAG. Anyone can now install it with:"
echo "  curl -fsSL https://raw.githubusercontent.com/Pallepadehat/QuackieChan/main/install.sh | bash"
