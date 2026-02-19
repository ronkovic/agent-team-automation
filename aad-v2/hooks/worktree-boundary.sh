#!/bin/bash
# Hook B: Worktree 境界チェック
# Claude Code PreToolUse (Write|Edit) フック
# AAD_WORKTREE_PATH 外への書き込みを阻止する

# TOOL_INPUT から file_path を抽出 (スペースあり/なし両対応: H8修正)
FILE_PATH=$(echo "$TOOL_INPUT" | grep -oE '"file_path"\s*:\s*"[^"]*"' | head -1 | sed 's/.*"file_path"\s*:\s*"//;s/"$//')
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
