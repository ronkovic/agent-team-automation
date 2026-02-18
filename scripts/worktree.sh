#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
使用方法: $(basename "$0") <サブコマンド> [引数...]

サブコマンド:
  create-parent <project_dir> <parent_branch> [<feature_name>]  worktreeベースディレクトリと親ブランチを作成
  create-task <worktree_base> <agent_name> <branch_name> <parent_branch>  タスク用worktreeを作成
  remove <worktree_path> [<branch_name>]          worktreeを削除
  list [<worktree_base>]                          worktree一覧を表示
  cleanup <worktree_base>                         全worktreeをクリーンアップ
  resolve-gitdir <worktree_path>                  壊れた.gitファイルを修復
EOF
  exit 1
}

cmd_create_parent() {
  local project_dir="${1:?エラー: project_dir が必要です}"
  local parent_branch="${2:?エラー: parent_branch が必要です}"
  local feature_name="${3:-}"

  local worktree_base
  if [[ -n "$feature_name" ]]; then
    worktree_base="${project_dir}-${feature_name}-wt"
  else
    worktree_base="${project_dir}-wt"
  fi

  # worktreeベースディレクトリを作成
  if [[ ! -d "$worktree_base" ]]; then
    mkdir -p "$worktree_base"
    echo "✓ worktreeベースディレクトリを作成しました: $worktree_base"
  else
    echo "worktreeベースディレクトリは既に存在します: $worktree_base"
  fi

  # 親ブランチが存在しない場合は作成
  cd "$project_dir"
  if ! git rev-parse --verify "$parent_branch" >/dev/null 2>&1; then
    git branch "$parent_branch"
    echo "✓ 親ブランチを作成しました: $parent_branch"
  else
    echo "親ブランチは既に存在します: $parent_branch"
  fi

  # project-config.json に worktreeDir を記録
  local config_dir="${project_dir}/.claude/aad"
  local config_file="${config_dir}/project-config.json"
  mkdir -p "$config_dir"

  if [[ -f "$config_file" ]]; then
    # 既存のconfig.jsonを更新
    local tmp_file
    tmp_file=$(mktemp)
    if command -v jq >/dev/null 2>&1; then
      jq --arg wtd "$worktree_base" --arg fn "$feature_name" \
        '.worktreeDir = $wtd | if $fn != "" then .featureName = $fn else . end' \
        "$config_file" > "$tmp_file"
      mv "$tmp_file" "$config_file"
    else
      # jqがない場合はPythonで処理
      python3 -c "
import json, sys
with open('$config_file', 'r') as f:
    data = json.load(f)
data['worktreeDir'] = '$worktree_base'
if '$feature_name':
    data['featureName'] = '$feature_name'
with open('$config_file', 'w') as f:
    json.dump(data, f, indent=2)
"
    fi
  else
    # 新規作成
    if [[ -n "$feature_name" ]]; then
      cat > "$config_file" <<JSONEOF
{
  "worktreeDir": "$worktree_base",
  "featureName": "$feature_name"
}
JSONEOF
    else
      cat > "$config_file" <<JSONEOF
{
  "worktreeDir": "$worktree_base"
}
JSONEOF
    fi
  fi
  echo "✓ project-config.json に worktreeDir を記録しました"
}

cmd_create_task() {
  local worktree_base="${1:?エラー: worktree_base が必要です}"
  local agent_name="${2:?エラー: agent_name が必要です}"
  local branch_name="${3:?エラー: branch_name が必要です}"
  local parent_branch="${4:?エラー: parent_branch が必要です}"

  local worktree_path="${worktree_base}/${agent_name}"

  git worktree add "$worktree_path" -b "feature/${branch_name}" "$parent_branch"
  echo "✓ タスク用worktreeを作成しました: $worktree_path"
  echo "$worktree_path"
}

cmd_remove() {
  local worktree_path="${1:?エラー: worktree_path が必要です}"
  local branch_name="${2:-}"

  # worktreeを削除
  if git worktree remove "$worktree_path" 2>/dev/null; then
    echo "✓ worktreeを削除しました: $worktree_path"
  else
    echo "通常の削除に失敗しました。--force で再試行します..."
    git worktree remove --force "$worktree_path"
    echo "✓ worktreeを強制削除しました: $worktree_path"
  fi

  # ブランチ削除（指定された場合）
  if [[ -n "$branch_name" ]]; then
    if git branch -d "feature/${branch_name}" 2>/dev/null; then
      echo "✓ ブランチを削除しました: feature/${branch_name}"
    else
      echo "通常のブランチ削除に失敗しました。-D で再試行します..."
      git branch -D "feature/${branch_name}"
      echo "✓ ブランチを強制削除しました: feature/${branch_name}"
    fi
  fi
}

cmd_list() {
  local worktree_base="${1:-}"

  if [[ -n "$worktree_base" ]]; then
    git worktree list | grep "$worktree_base" || echo "指定されたベースディレクトリ配下にworktreeはありません: $worktree_base"
  else
    git worktree list
  fi
}

cmd_cleanup() {
  local worktree_base="${1:?エラー: worktree_base が必要です}"

  # worktree_base配下の全worktreeを削除
  if [[ -d "$worktree_base" ]]; then
    for wt_dir in "$worktree_base"/*/; do
      if [[ -d "$wt_dir" ]]; then
        local wt_path
        wt_path=$(cd "$wt_dir" && pwd)
        if git worktree remove "$wt_path" 2>/dev/null; then
          echo "✓ worktreeを削除しました: $wt_path"
        else
          git worktree remove --force "$wt_path" 2>/dev/null || true
          echo "✓ worktreeを強制削除しました: $wt_path"
        fi
      fi
    done
  fi

  # feature/*ブランチを全削除
  local branches
  branches=$(git branch --list 'feature/*' | sed 's/^[* ]*//' || true)
  if [[ -n "$branches" ]]; then
    while IFS= read -r branch; do
      if git branch -d "$branch" 2>/dev/null; then
        echo "✓ ブランチを削除しました: $branch"
      else
        git branch -D "$branch" 2>/dev/null || true
        echo "✓ ブランチを強制削除しました: $branch"
      fi
    done <<< "$branches"
  else
    echo "削除対象のfeature/*ブランチはありません"
  fi

  # worktree_baseディレクトリ自体を削除
  if [[ -d "$worktree_base" ]]; then
    rm -rf "$worktree_base"
    echo "✓ worktreeベースディレクトリを削除しました: $worktree_base"
  fi

  # git worktree pruneを実行
  git worktree prune
  echo "✓ クリーンアップが完了しました"
}

cmd_resolve_gitdir() {
  local worktree_path="${1:?エラー: worktree_path が必要です}"

  if [[ ! -d "$worktree_path" ]]; then
    echo "エラー: worktreeパスが存在しません: $worktree_path"
    exit 1
  fi

  local git_file="${worktree_path}/.git"
  if [[ -f "$git_file" ]]; then
    echo ".gitファイルを確認中: $git_file"
    local gitdir
    gitdir=$(cat "$git_file" | sed 's/^gitdir: //')
    if [[ ! -d "$gitdir" ]]; then
      echo "警告: .gitファイルが指すディレクトリが存在しません: $gitdir"
      echo "git worktree repair を実行します..."
    fi
  fi

  git worktree repair
  echo "✓ worktreeの修復が完了しました: $worktree_path"
}

# メインエントリポイント
if [[ $# -lt 1 ]]; then
  usage
fi

subcommand="$1"
shift

case "$subcommand" in
  create-parent)  cmd_create_parent "$@" ;;
  create-task)    cmd_create_task "$@" ;;
  remove)         cmd_remove "$@" ;;
  list)           cmd_list "$@" ;;
  cleanup)        cmd_cleanup "$@" ;;
  resolve-gitdir) cmd_resolve_gitdir "$@" ;;
  *)
    echo "エラー: 不明なサブコマンド: $subcommand"
    usage
    ;;
esac
