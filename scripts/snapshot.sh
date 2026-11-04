#!/bin/bash
# デバッグ版を架空のカードで起動し、パネルの見た目を PNG に書き出す
# 使い方: scripts/snapshot.sh <出力先の絶対パス>
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$1"
EMPTY="$(mktemp -d)"

"${PROJECT_DIR}/scripts/build-app.sh" debug >/dev/null
LIVE_ADVISOR_SESSIONS_ROOT="${EMPTY}" \
    "${PROJECT_DIR}/dist/助言くん.app/Contents/MacOS/助言くん" --fixture --snapshot "${OUTPUT}"
rm -rf "${EMPTY}"
ls -l "${OUTPUT}"
