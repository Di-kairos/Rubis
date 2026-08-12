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

# Идентичность нужна раньше подписи образа: ею же подписывается вложенный
# audio-verify и перезапечатывается бандл. Без Developer ID (сборка ad-hoc)
# подписываем прочерком — локально этого достаточно, нотаризация всё равно
# не пойдёт.
# Именно та идентичность, которой подписывал Xcode (DEVELOPMENT_TEAM в
# Config/Escapement.xcconfig): чужой Developer ID в связке дал бы приложение и
# фреймворки с разными Team ID — codesign промолчит, а dyld откажется грузить.
team="TA24A89R8H"
identity=$(security find-identity -v -p codesigning \
    | awk -F'"' -v team="($team)" '/Developer ID Application/ && index($2, team) {print $2; exit}')
identity="${identity:--}"
# Ad-hoc не умеет защищённый штамп времени: с ним codesign просто откажет.
if [[ "$identity" == "-" ]]; then stamp=(); else stamp=(--timestamp); fi

# audio-verify едет внутри бандла (D-011): доказательство bit-perfect должно
# быть у того, кто слушает, а не только у того, кто собирает. Отдельным файлом
# в образе он потянул бы за собой копию всех десяти фреймворков-декодеров —
# внутри бандла он берёт те же, что и приложение.
echo "==> audio-verify"
# Архитектура — как у приложения (ARCHS = arm64): на Intel-хосте SwiftPM собрал
# бы x86_64, и бинарь не подхватил бы arm64-фреймворки из бандла.
swift build -c release --arch arm64 --package-path "$repo/Tools/audio-verify" | tail -1
helper="$repo/Tools/audio-verify/.build/arm64-apple-macosx/release/audio-verify"
cp "$helper" "$app/Contents/MacOS/audio-verify"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$app/Contents/MacOS/audio-verify"
codesign --force --sign "$identity" --options runtime "${stamp[@]}" \
    --entitlements "$repo/Tools/audio-verify/audio-verify.entitlements" \
    "$app/Contents/MacOS/audio-verify"
# Вложенный бинарь ломает печать бандла — запечатываем заново поверх него.
# Без --deep: вложенные подписи (Sparkle, фреймворки) уже поставлены Xcode
# изнутри наружу, и --deep раскатал бы по ним чужие entitlements.
codesign --force --sign "$identity" --options runtime "${stamp[@]}" \
    --entitlements "$repo/App/Escapement.entitlements" "$app"
codesign --verify --deep --strict "$app"
# Смоук-проверка: под hardened runtime библиотечная валидация пускает
# фреймворки только с тем же Team ID, что у процесса. Пусть образ ломается
# здесь, а не у слушателя после нотаризации. Код 2 — штатный ответ утилиты
# «фикстур нет»; до него она успевает загрузить все десять фреймворков.
smoke=$("$app/Contents/MacOS/audio-verify" /nonexistent-fixtures 2>&1) && smoke_status=0 ||
    smoke_status=$?
if [[ $smoke_status -ne 2 || "$smoke" != *"No fixtures"* ]]; then
    echo "$smoke" >&2
    echo "audio-verify does not start inside the bundle — check framework Team IDs" >&2
    exit 1
fi

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

# Подписываем сам образ той же идентичностью — иначе Gatekeeper оценивает его
# как «no usable signature» (приложение внутри при этом заверено). Подпись
# ставится ДО отправки: нотаризация заверяет уже подписанный образ.
if [[ "$identity" != "-" ]]; then
    codesign --force --sign "$identity" --timestamp "$dmg"
fi

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
# Не роняем релиз из-за вердикта — подпись обновления ниже нужна в любом случае.
spctl --assess --type open --context context:primary-signature -v "$dmg" || true

# Подпись обновления для Sparkle. Утилита приезжает из SPM вместе с пакетом,
# приватный ключ EdDSA лежит в связке ключей машины — ни внешний диск, ни
# файлы репозитория для этого не нужны (клон с GitHub выпускает релиз сам).
echo "==> Appcast enclosure"
sign_update="$derived/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ -x "$sign_update" ]]; then
    "$sign_update" "$dmg"
    echo "sha256: $(shasum -a 256 "$dmg" | cut -d' ' -f1)"
else
    echo "sign_update not found in SPM artifacts — sign the DMG manually"
fi
