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

# Нотаризация: Apple заверяет пакет, Gatekeeper открывает его на чужой машине
# двойным кликом (без right-click → Open). Профиль ключницы создаётся один раз:
#   xcrun notarytool store-credentials rubis --apple-id <id> --team-id <team> --password <app-specific>
# Профиля нет — выходим с готовым, но не заверенным DMG (RUBIS_SKIP_NOTARIZE=1
# пропускает шаг осознанно).
if [[ -n "${RUBIS_SKIP_NOTARIZE:-}" ]]; then
    echo "==> Notarization skipped (RUBIS_SKIP_NOTARIZE)"
    exit 0
fi
if ! xcrun notarytool history --keychain-profile rubis >/dev/null 2>&1; then
    echo "==> No 'rubis' notary profile — DMG is signed but NOT notarized"
    exit 0
fi

echo "==> Notarize (submitting to Apple, takes a few minutes)"
xcrun notarytool submit "$dmg" --keychain-profile rubis --wait

echo "==> Staple"
xcrun stapler staple "$dmg"
# Финальная проверка глазами Gatekeeper: так пакет увидит чужой Mac.
spctl --assess --type open --context context:primary-signature -v "$dmg"
