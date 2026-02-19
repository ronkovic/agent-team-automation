# AAD v2 — Claude Code Hooks

Claude Code の `PreToolUse` フック機構を利用した安全フック集。
Git worktree 並列実装中の意図しない操作を防ぐ。

## セットアップ

`.claude/hooks.json` に以下の JSON を追記してください。

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/aad-v2/hooks/memory-check.sh"
          }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/aad-v2/hooks/worktree-boundary.sh"
          }
        ]
      }
    ]
  }
}
```

`/path/to/aad-v2/hooks/` はご自身の環境のパスに置き換えてください。
Plugin として配置した場合: `~/.claude/plugins/aad-v2/hooks/`

---

## Hook A: メモリ安全チェック (`memory-check.sh`)

**対象**: `Bash` ツール (`PreToolUse`)
**目的**: 空きメモリが 512MB 未満の場合に重いBash操作をブロックする

### 動作

- **macOS**: `vm_stat` で free + inactive + purgeable ページを集計
- **Linux**: `/proc/meminfo` の `MemAvailable` を読む
- **その他**: 判定不能のため何もしない（ブロックしない）
- 空きメモリ < 512MB → `BLOCK:` メッセージを出力して操作を阻止

### スクリプト本体

```bash
#!/bin/bash
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
```

---

## Hook B: Worktree 境界チェック (`worktree-boundary.sh`)

**対象**: `Write|Edit` ツール (`PreToolUse`)
**目的**: サブエージェントが割り当て外の worktree やプロジェクト外に書き込むことを防ぐ

### 動作

- `$TOOL_INPUT` から `file_path` を抽出（python3優先、POSIX grepフォールバック）
- 相対パスへの書き込みをブロック（絶対パス必須）
- `AAD_WORKTREE_PATH` 配下への書き込みのみ許可
- `AAD_PROJECT_DIR/.claude/` 配下への書き込みは状態管理用に許可
- `AAD_WORKTREE_PATH` が未設定の場合は何もしない（worktree外エージェントには影響なし）

### 環境変数

`AAD_WORKTREE_PATH`: オーケストレーターがサブエージェント起動時に設定する。
各エージェントの割り当て worktree パス（例: `/path/to/project-feature-wt/agent-order`）。

`AAD_PROJECT_DIR`: プロジェクトルートの絶対パス。設定すると `${AAD_PROJECT_DIR}/.claude/` 配下への書き込みが状態管理用に許可される。未設定の場合、`.claude/` への書き込みは `AAD_WORKTREE_PATH` 配下にある場合のみ許可。

### スクリプト本体

```bash
#!/bin/bash
# Hook B: Worktree 境界チェック
# Claude Code PreToolUse (Write|Edit) フック
# AAD_WORKTREE_PATH 外への書き込みを阻止する

# TOOL_INPUT から file_path を抽出 (ポータブル版: python3優先、grepフォールバック: H8修正)
if command -v python3 >/dev/null 2>&1; then
  FILE_PATH=$(echo "$TOOL_INPUT" | python3 -c "
import json,sys
try:
  d=json.loads(sys.stdin.read())
  print(d.get('file_path',''))
except Exception:
  pass
" 2>/dev/null)
else
  # フォールバック: grep -oE で値部分を抽出 ([[:space:]] はPOSIX準拠)
  FILE_PATH=$(echo "$TOOL_INPUT" \
    | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 \
    | grep -oE '"[^"]*"$' \
    | tr -d '"')
fi
[ -z "$FILE_PATH" ] && exit 0

# AAD_WORKTREE_PATH が未設定の場合はチェックしない（Wave 0 やオーケストレーター自身）
[ -z "${AAD_WORKTREE_PATH:-}" ] && exit 0

# 相対パスは境界チェック不可のため拒否 (C3修正: 許可→拒否)
if [[ "$FILE_PATH" != /* ]]; then
  echo "BLOCK: 相対パスへの書き込みはworktreeエージェントでは許可されていません。"
  echo "  対象ファイル: $FILE_PATH"
  echo "  絶対パスを使用してください。"
  exit 1
fi

# AAD_WORKTREE_PATH 配下への書き込みは許可
# (C1修正: *-wt/* の過剰許可を削除し、明示的なパスチェックのみ使用)
[[ "$FILE_PATH" == "${AAD_WORKTREE_PATH}"/* ]] && exit 0

# AAD_PROJECT_DIR が設定されている場合、その .claude/ 配下への書き込みは状態管理用に許可
# (C2修正: */.claude/* の全許可を削除し、プロジェクト固有のパスのみ許可)
if [[ -n "${AAD_PROJECT_DIR:-}" ]]; then
  [[ "$FILE_PATH" == "${AAD_PROJECT_DIR}/.claude/"* ]] && exit 0
fi

echo "BLOCK: Worktree境界外への書き込みが検出されました。"
echo "  対象ファイル: $FILE_PATH"
echo "  許可範囲: ${AAD_WORKTREE_PATH}/"
echo "このエージェントは割り当て worktree 外を変更できません。"
```

---

## 注意事項

- フックは Claude Code の hooks 機能を使用します（ `claude hooks` コマンドで設定可能）
- Hook B は `AAD_WORKTREE_PATH` が設定されたサブエージェント環境でのみ動作します
- フックのデバッグは `AAD_HOOK_DEBUG=1` 環境変数で詳細ログを有効化できます（実装済み）
