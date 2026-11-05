#!/usr/bin/env python3
"""架空の会議を events.jsonl へ書き出す（スピーカーで音を出さず、本物の会議も使わない）。

使い方: scripts/replay.py <Sessions の置き場> [1行あたりの秒数]
"""
import datetime
import json
import os
import sys
import time

MEETING = [
    ("others", "そらまめスペースの田中です。本日はお時間ありがとうございます。前回に続き、貸し会議室の予約サイトのデータベース更新のご相談です。"),
    ("me", "よろしくお願いします。今の状況から教えていただけますか。"),
    ("others", "PostgreSQL 14 で動いていて、予約は一日に三千件ほどです。"),
    ("me", "なるほど、更新を急ぐ理由は何でしょうか。"),
    ("others", "サポートが切れると聞いたので、新しい版へ上げたいと考えています。"),
    ("others", "そこで質問なんですが、PostgreSQL 14 のサポートはいつまでですか。"),
    ("me", "すみません、正確な日付を覚えていないので、確認します。"),
    ("others", "お願いします。あわせて、次の版へ上げるときの注意点も知りたいです。"),
    ("me", "承知しました。そちらも調べておきます。"),
    ("others", "更新の方式は社内でも意見が割れていまして、一括で更新するか、複製して切り替えるか決めきれていません。"),
    ("others", "一括更新は手順が単純だけれどサイトを止めることになる。複製して切り替えるのは止まらないけれど準備が大変です。"),
    ("me", "サイトはどのくらいなら止められるんでしょうか。"),
    ("others", "そこも悩ましいところで、現場は三十分までと言っていますが、根拠があるわけではありません。"),
    ("me", "となると、どちらがいいか判断が難しいですね。"),
    ("others", "そうなんです。四月の更新までに方向性だけでも決めたいのですが、どうしましょう。"),
    ("me", "手間と停止時間のどちらを優先するかで答えが変わりそうです。"),
    ("others", "手間を減らしたい人と、止めたくない人がいて、議論が同じところを回っています。"),
    ("me", "まず検証環境で試して、実際の停止時間を測ってから決めるやり方もありますね。"),
    ("others", "それも案ですが、試す期間が取れるかは分かりません。"),
    ("me", "なるほど。次回までに論点を整理しましょう。"),
]


def main() -> int:
    root = sys.argv[1]
    interval = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
    now = datetime.datetime.now()
    folder = os.path.join(root, now.strftime("%Y-%m-%d_%H-%M-%S"))
    os.makedirs(folder)
    path = os.path.join(folder, "events.jsonl")

    def write(kind, payload):
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(path, "a", encoding="utf-8") as f:
            # 本体と同じくスペースなしで書く。助言さんはこの形のバイト列で確定行を絞り込む
            f.write(json.dumps({"type": kind, "timestamp": stamp, "payload": payload}, ensure_ascii=False, separators=(",", ":")) + "\n")

    write("session_started", {"recognizer": "replay"})
    for speaker, text in MEETING:
        time.sleep(interval)
        write("recognition", {"text": text[: len(text) // 2], "final": "false", "speaker": speaker})
        write("recognition", {"text": text, "final": "true", "speaker": speaker})
    time.sleep(interval)
    write("session_stopped", {})
    print(folder)
    return 0


if __name__ == "__main__":
    sys.exit(main())
