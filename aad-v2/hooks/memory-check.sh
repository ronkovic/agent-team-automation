#!/bin/bash
[[ "${AAD_HOOK_DEBUG:-}" == "1" ]] && set -x
# Hook A: メモリ安全チェック
# Claude Code PreToolUse (Bash) フック
# 空きメモリが 512MB 未満の場合に BLOCK を出力する

if command -v vm_stat >/dev/null 2>&1; then
  # macOS: Pages free + inactive + purgeable を集計
  FREE=$(vm_stat | awk '/Pages (free|inactive|purgeable)/ {sum+=$NF} END {printf "%d", sum*4096/1048576}')
elif [ -f /proc/meminfo ]; then
  # Linux: MemAvailable (MB)
  FREE=$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo)
else
  exit 0  # 判定不能 → ブロックしない
fi

if [ "${FREE:-0}" -lt 512 ]; then
  echo "BLOCK: メモリ不足 (${FREE}MB free < 512MB)。重い操作を中断してください。"
fi
