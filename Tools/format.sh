#!/bin/zsh
# Formats all Swift sources in-place using the toolchain's swift-format
# with the .swift-format config at the repo root. Run before every commit.
set -euo pipefail
cd "$(dirname "$0")/.."

swift format --in-place --recursive --configuration .swift-format \
    App Packages Tools 2>/dev/null || \
swift format format --in-place --recursive --configuration .swift-format \
    App Packages Tools

echo "swift-format: done"
