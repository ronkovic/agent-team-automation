#!/usr/bin/env bash
# 汎用リトライラッパー
# Usage: retry.sh [--max N] [--delay S] [--backoff] -- <command...>
# デフォルト: 最大3回、初期待機2秒、指数バックオフなし
set -euo pipefail

MAX_RETRIES=3
DELAY=2
BACKOFF=false
CMD=()

# 引数パース
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max)
      shift
      MAX_RETRIES="$1"
      ;;
    --delay)
      shift
      DELAY="$1"
      ;;
    --backoff)
      BACKOFF=true
      ;;
    --)
      shift
      CMD=("$@")
      break
      ;;
    *)
      echo "エラー: 不明な引数: $1" >&2
      echo "使用方法: $(basename "$0") [--max N] [--delay S] [--backoff] -- <command...>" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ ${#CMD[@]} -eq 0 ]]; then
  echo "使用方法: $(basename "$0") [--max N] [--delay S] [--backoff] -- <command...>" >&2
  exit 1
fi

attempt=0
current_delay=$DELAY

while [[ $attempt -lt $MAX_RETRIES ]]; do
  attempt=$((attempt + 1))

  if "${CMD[@]}"; then
    [[ $attempt -gt 1 ]] && echo "✓ リトライ ${attempt} 回目で成功" >&2
    exit 0
  fi

  if [[ $attempt -lt $MAX_RETRIES ]]; then
    echo "⚠ 試行 ${attempt}/${MAX_RETRIES} 失敗。${current_delay}秒後にリトライ..." >&2
    if [[ "$current_delay" -gt 0 ]]; then
      sleep "$current_delay"
    fi
    if [[ "$BACKOFF" == "true" ]]; then
      current_delay=$((current_delay * 2))
    fi
  fi
done

echo "✗ 最大リトライ回数 (${MAX_RETRIES}) 達成。コマンド失敗: ${CMD[*]}" >&2
exit 1
