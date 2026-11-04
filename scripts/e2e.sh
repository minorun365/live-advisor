#!/bin/bash
# 架空の会議を流し、Claude Code を実際に呼んで最後まで通す。ログイン中の Claude の利用枠を少し使う
# 使い方: scripts/e2e.sh <結果を置くフォルダの絶対パス>
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$1"
ROOT="${WORK}/sessions"
LOG="${HOME}/Library/Logs/LiveAdvisor/live-advisor.log"
mkdir -p "${ROOT}" "$(dirname "${LOG}")"

touch "${LOG}"; BEFORE=$(wc -l < "${LOG}")

LIVE_ADVISOR_FAST=1 \
LIVE_ADVISOR_PRESS_DIRECTION=1 \
LIVE_ADVISOR_PRESS_NOW=1 \
LIVE_ADVISOR_SESSIONS_ROOT="${ROOT}" \
    "${PROJECT_DIR}/dist/助言さん.app/Contents/MacOS/助言さん" &
APP=$!
sleep 2

FOLDER=$(python3 "${PROJECT_DIR}/scripts/replay.py" "${ROOT}" 4)

# 最後の判定が戻るのを待ってから、カードの状態が落ち着くまで待つ（最長6分）
sleep 20
for _ in $(seq 1 72); do
    sleep 5
    python3 - "${FOLDER}/advisor-cards.json" <<'EOF' && break
import json, sys
try:
    cards = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(1 if any(c["state"] == "running" for c in cards) else 0)
EOF
done
sleep 3
kill "${APP}" 2>/dev/null

echo "--- 会議フォルダ: ${FOLDER}"
ls -1 "${FOLDER}"
echo "--- カード"
python3 - "${FOLDER}/advisor-cards.json" <<'EOF'
import json, sys
for c in json.load(open(sys.argv[1])):
    print(json.dumps({k: c.get(k) for k in ["kind","requested","title","note","state","startedAutomatically","confidence","searchQuestions","conclusion","recommendation","reasoning","askNext","unknowns","options","sources","failure"]}, ensure_ascii=False, indent=1))
EOF
echo "--- 調査へ送った問い"
cat "${FOLDER}/advisor-queries.jsonl" 2>/dev/null
echo "--- 消費"
tail -n +"$((BEFORE + 1))" "${LOG}"
