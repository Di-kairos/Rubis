#!/bin/zsh
# Собирает установочный DMG: Release-сборка + симлинк /Applications.
# Использование: Tools/make-dmg.sh [output-dir]  (по умолчанию ~/Desktop)
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="${1:-$HOME/Desktop}"
derived="$(mktemp -d)/derived"
stage="$(mktemp -d)/RubisMusic"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> Release build"
xcodebuild -project "$repo/Escapement.xcodeproj" -scheme Escapement \
    -configuration Release -derivedDataPath "$derived" build | tail -1

app="$derived/Build/Products/Release/Rubis Music.app"
version=$(defaults read "$app/Contents/Info" CFBundleShortVersionString)
dmg="$out_dir/RubisMusic-$version.dmg"

echo "==> Staging"
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"

echo "==> DMG"
rm -f "$dmg"
hdiutil create -volname "Rubis Music $version" -srcfolder "$stage" \
    -fs HFS+ -format UDZO -quiet "$dmg"

echo "==> Verify"
hdiutil verify -quiet "$dmg" && echo "DMG OK: $dmg"
