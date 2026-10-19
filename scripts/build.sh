#!/bin/zsh
# Builds "Quackie Chan.app" into build/ with xcodebuild (MLX needs Xcode's Metal compiler).
#
# Signing: your Apple Development certificate when there is one (so macOS remembers permissions across rebuilds),
# otherwise ad hoc. QUACKIE_SIGN=developer-id signs with your Developer ID Application certificate and a secure
# timestamp instead, which is what notarization (and so a release) needs.
set -euo pipefail
cd "$(dirname "$0")/.."

# Regenerate the project if XcodeGen is around, so it matches project.yml.
command -v xcodegen >/dev/null && xcodegen generate --quiet

SIGNING=()
# Read into a variable rather than `| grep -q`, which can trip pipefail with SIGPIPE.
IDENTITIES=$(security find-identity -v -p codesigning)
if [[ "${QUACKIE_SIGN:-}" == "developer-id" ]]; then
  [[ "$IDENTITIES" == *'"Developer ID Application'* ]] \
    || { echo "No Developer ID Application certificate in your keychain."; exit 1; }
  SIGNING=(CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=537P4FPMZ4
    OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)  # no get-task-allow: Apple refuses to notarize it
elif [[ "$IDENTITIES" != *'"Apple Development'* ]]; then
  echo "No Apple Development certificate found; signing ad hoc."
  SIGNING=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

APP="build/DerivedData/Build/Products/Release/Quackie Chan.app"
# A failed build must never leave an older app behind to be picked up below.
rm -rf "$APP"
mkdir -p build
if ! xcodebuild -project QuackieChan.xcodeproj -scheme QuackieChan -configuration Release \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' \
  -skipMacroValidation -skipPackagePluginValidation \
  "${SIGNING[@]}" build > build/xcodebuild.log 2>&1; then
  grep -E "error:" build/xcodebuild.log | sort -u | head -20
  echo "Build failed. The whole log is in build/xcodebuild.log"
  exit 1
fi
grep -E "warning: .*QuackieChan/" build/xcodebuild.log | sort -u || true

[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }

# Sparkle's helpers (the installer, the updater app) come signed ad hoc, and Xcode only re-signs the framework around
# them. Apple's notarization, and Sparkle's own check of an update, need every piece signed by us.
if [[ "${QUACKIE_SIGN:-}" == "developer-id" ]]; then
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  sign() { codesign --force --sign "Developer ID Application" --options runtime --timestamp "$@"; }
  sign "$SPARKLE/XPCServices/Installer.xpc"
  sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
  sign "$SPARKLE/Autoupdate"
  sign "$SPARKLE/Updater.app"
  sign "$APP/Contents/Frameworks/Sparkle.framework"
  # And the app again, as its signature covers the framework.
  sign --preserve-metadata=entitlements,requirements,flags "$APP"
  codesign --verify --deep --strict "$APP" || { echo "The app's signature doesn't check out."; exit 1; }
fi
rm -rf "build/Quackie Chan.app"
ditto "$APP" "build/Quackie Chan.app"
echo "Built build/Quackie Chan.app"
echo "Run it with: open \"build/Quackie Chan.app\""
