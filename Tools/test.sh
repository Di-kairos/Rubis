#!/bin/zsh
# Runs `swift test` for every package.
# ponytail: extra -F/-rpath flags are a Command Line Tools workaround (Swift Testing
# lives outside the default search paths there); with full Xcode installed they are
# harmless and this script keeps working unchanged.
set -euo pipefail
cd "$(dirname "$0")/.."

CLT_DEV=/Library/Developer/CommandLineTools/Library/Developer
EXTRA=()
if [[ -d "$CLT_DEV/Frameworks/Testing.framework" ]]; then
    EXTRA=(
        -Xswiftc -F -Xswiftc "$CLT_DEV/Frameworks"
        -Xlinker -F -Xlinker "$CLT_DEV/Frameworks"
        -Xlinker -rpath -Xlinker "$CLT_DEV/Frameworks"
        -Xlinker -rpath -Xlinker "$CLT_DEV/usr/lib"
    )
fi

for pkg in Packages/*; do
    echo "=== swift test: ${pkg:t} ==="
    swift test --package-path "$pkg" "${EXTRA[@]}"
done
echo "All package tests passed."
