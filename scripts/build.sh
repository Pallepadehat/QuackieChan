#!/bin/zsh
# Builds "Quackie Chan.app" into build/ with xcodebuild (MLX needs Xcode's Metal compiler).
set -euo pipefail
cd "$(dirname "$0")/.."

# Regenerate the project if XcodeGen is around, so it matches project.yml.
command -v xcodegen >/dev/null && xcodegen generate --quiet

# Sign with your Apple Development certificate when there is one, so macOS remembers permissions
# across rebuilds. Otherwise sign ad hoc.
SIGNING=()
if ! security find-identity -v -p codesigning | grep -q '"Apple Development'; then
  echo "No Apple Development certificate found; signing ad hoc."
  SIGNING=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

xcodebuild -project QuackieChan.xcodeproj -scheme QuackieChan -configuration Release \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' \
  -skipMacroValidation -skipPackagePluginValidation \
  "${SIGNING[@]}" build | grep -E "error|warning: .*QuackieChan/|BUILD" || true

APP="build/DerivedData/Build/Products/Release/Quackie Chan.app"
[[ -d "$APP" ]] || { echo "Build failed"; exit 1; }
rm -rf "build/Quackie Chan.app"
ditto "$APP" "build/Quackie Chan.app"
echo "Built build/Quackie Chan.app"
echo "Run it with: open \"build/Quackie Chan.app\""
