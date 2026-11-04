#!/bin/bash
# Release 版を作って ~/Applications へ入れ、起動し直す。ログイン時の起動はアプリ自身が登録する
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${HOME}/Applications/助言くん.app"

"${PROJECT_DIR}/scripts/test.sh"
"${PROJECT_DIR}/scripts/build-app.sh" release >/dev/null

pkill -x "助言くん" 2>/dev/null || true
sleep 1
mkdir -p "${HOME}/Applications"
rm -rf "${DEST}"
ditto "${PROJECT_DIR}/dist/助言くん.app" "${DEST}"
open "${DEST}"
sleep 2
pgrep -x "助言くん" >/dev/null && echo "起動しました: ${DEST}"
