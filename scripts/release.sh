#!/bin/zsh
# Makes a release: builds a notarized QuackieChan.dmg and publishes it as a GitHub release, where install.sh finds
# it. The version comes from MARKETING_VERSION in project.yml.
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

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" build/QuackieChan.dmg --title "Quackie Chan $VERSION" "${NOTES[@]}"
echo "Released $TAG. Anyone can now install it with:"
echo "  curl -fsSL https://raw.githubusercontent.com/Pallepadehat/QuackieChan/main/install.sh | bash"
