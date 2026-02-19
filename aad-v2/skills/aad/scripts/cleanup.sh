#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
使用方法: $(basename "$0") <サブコマンド> [引数...]

サブコマンド:
  run [<project_dir>]       worktreeクリーンアップとstate.jsonアーカイブを実行
  orphans [<project_dir>]   孤児worktreeとマージ済みブランチを削除
EOF
  exit 1
}

cmd_run() {
  local project_dir="${1:-.}"
  project_dir=$(cd "$project_dir" && pwd)

  local config_file="${project_dir}/.claude/aad/project-config.json"

  if [[ ! -f "$config_file" ]]; then
    echo "エラー: project-config.json が見つかりません: $config_file"
    exit 1
  fi

  # worktreeDirを取得
  local worktree_dir
  if command -v jq >/dev/null 2>&1; then
    worktree_dir=$(jq -r '.worktreeDir' "$config_file")
  else
    worktree_dir=$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['worktreeDir'])" "$config_file")
  fi

  if [[ -z "$worktree_dir" ]] || [[ "$worktree_dir" == "null" ]]; then
    echo "エラー: worktreeDirが設定されていません"
    exit 1
  fi

  # worktree.sh cleanupを実行
  echo "worktreeのクリーンアップを実行中..."
  bash "${SCRIPT_DIR}/worktree.sh" cleanup "$worktree_dir"

  # state.jsonをアーカイブ
  local state_file="${project_dir}/.claude/aad/state.json"
  if [[ -f "$state_file" ]]; then
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local archive_dir="${project_dir}/.claude/aad/archive/${timestamp}"
    mkdir -p "$archive_dir"
    cp "$state_file" "${archive_dir}/state.json"
    echo "✓ state.json をアーカイブしました: ${archive_dir}/state.json"
  else
    echo "state.json が見つかりません。アーカイブをスキップします。"
  fi

  echo "✓ クリーンアップ完了"
}

cmd_orphans() {
  local project_dir="${1:-.}"
  project_dir=$(cd "$project_dir" && pwd)
  cd "$project_dir"

  local deleted_count=0

  # 登録済みworktreeを列挙し、存在しないディレクトリを検出
  echo "孤児worktreeを検出中..."
  local worktree_list
  worktree_list=$(git worktree list --porcelain)

  local current_path=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.+) ]]; then
      current_path="${BASH_REMATCH[1]}"
    fi
    if [[ -n "$current_path" ]] && [[ "$line" == "" || "$line" =~ ^$ ]]; then
      if [[ ! -d "$current_path" ]] && [[ "$current_path" != "$project_dir" ]]; then
        echo "  孤児検出: $current_path"
        deleted_count=$((deleted_count + 1))
      fi
      current_path=""
    fi
  done <<< "$worktree_list"
  # 最後の行にも対応
  if [[ -n "$current_path" ]] && [[ ! -d "$current_path" ]] && [[ "$current_path" != "$project_dir" ]]; then
    echo "  孤児検出: $current_path"
    deleted_count=$((deleted_count + 1))
  fi

  # git worktree pruneを実行
  git worktree prune
  echo "✓ git worktree prune を実行しました"

  # feature/*ブランチのうちマージ済みのものを削除
  echo "マージ済みfeatureブランチを検出中..."
  local merged_branches
  merged_branches=$(git branch --merged | grep 'feature/' | sed 's/^[* ]*//' || true)
  if [[ -n "$merged_branches" ]]; then
    while IFS= read -r branch; do
      git branch -d "$branch" 2>/dev/null || true
      echo "  ✓ マージ済みブランチを削除しました: $branch"
      deleted_count=$((deleted_count + 1))
    done <<< "$merged_branches"
  else
    echo "  マージ済みのfeature/*ブランチはありません"
  fi

  echo "✓ 孤児クリーンアップ完了 (削除リソース: ${deleted_count}件)"
}

# メインエントリポイント
if [[ $# -lt 1 ]]; then
  usage
fi

subcommand="$1"
shift

case "$subcommand" in
  run)     cmd_run "$@" ;;
  orphans) cmd_orphans "$@" ;;
  *)
    echo "エラー: 不明なサブコマンド: $subcommand"
    usage
    ;;
esac
