#!/bin/bash
# 使い方: scripts/build-app.sh [debug|release]（既定 release）
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="助言くん"
EXECUTABLE_NAME="LiveAdvisor"
CONFIG="${1:-release}"
BUILD_DIR="${PROJECT_DIR}/dist"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"

# SwiftUI のマクロは Command Line Tools に無く Xcode の中にしかない。文字起こしちゃんと同じ回避
BUILD_FLAGS=(--package-path "${PROJECT_DIR}")
if [ ! -f "$(xcrun --show-sdk-platform-path 2>/dev/null)/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
    for candidate in \
        "$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" \
        "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"; do
        if [ -f "${candidate}/libSwiftUIMacros.dylib" ]; then
            BUILD_FLAGS+=(-Xswiftc -plugin-path -Xswiftc "${candidate}")
            break
        fi
    done
fi

swift build -c "${CONFIG}" --product "${EXECUTABLE_NAME}" "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build -c "${CONFIG}" --package-path "${PROJECT_DIR}" --show-bin-path)"

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${EXECUTABLE_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
cp "${PROJECT_DIR}/Resources/FaceIcon.png" "${APP_DIR}/Contents/Resources/"
for name in "MenuBarIdle" "MenuBarListening" "MenuBarInsight"; do
    for scale in "" "@2x" "@3x"; do
        cp "${PROJECT_DIR}/Resources/${name}${scale}.png" "${APP_DIR}/Contents/Resources/"
    done
done

codesign \
    --force \
    --sign - \
    --requirements '=designated => identifier "com.minorun365.LiveAdvisor"' \
    "${APP_DIR}"
echo "${APP_DIR}"
