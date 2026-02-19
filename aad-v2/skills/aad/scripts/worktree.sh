#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
使用方法: $(basename "$0") <サブコマンド> [引数...]

サブコマンド:
  create-parent <project_dir> <parent_branch> [<feature_name>]   worktreeベースディレクトリと親ブランチを作成
  create-task <worktree_base> <agent_name> <branch_name> <parent_branch>  タスク用worktreeを作成
  setup-symlinks <project_dir> <worktree_path>                   共有依存のsymlink作成（node_modules/.venv等）
  remove <worktree_path> [<branch_name>]                         worktreeを削除
  list [<worktree_base>]                                         worktree一覧を表示
  cleanup <worktree_base>                                        全worktreeをクリーンアップ
  resolve-gitdir <worktree_path>                                 壊れた.gitファイルを修復
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

  if [[ ! -d "$worktree_base" ]]; then
    mkdir -p "$worktree_base"
    echo "✓ worktreeベースディレクトリを作成しました: $worktree_base"
  else
    echo "worktreeベースディレクトリは既に存在します: $worktree_base"
  fi

  if ! git -C "$project_dir" rev-parse --verify "$parent_branch" >/dev/null 2>&1; then
    git -C "$project_dir" branch "$parent_branch"
    echo "✓ 親ブランチを作成しました: $parent_branch"
  else
    echo "親ブランチは既に存在します: $parent_branch"
  fi

  local config_dir="${project_dir}/.claude/aad"
  local config_file="${config_dir}/project-config.json"
  mkdir -p "$config_dir"

  if [[ -f "$config_file" ]]; then
    local tmp_file
    tmp_file=$(mktemp)
    if command -v jq >/dev/null 2>&1; then
      jq --arg wtd "$worktree_base" --arg fn "$feature_name" \
        '.worktreeDir = $wtd | if $fn != "" then .featureName = $fn else . end' \
        "$config_file" > "$tmp_file"
      mv "$tmp_file" "$config_file"
    else
      python3 -c "
import json, sys
config_file, worktree_base, feature_name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(config_file, 'r') as f:
    data = json.load(f)
data['worktreeDir'] = worktree_base
if feature_name:
    data['featureName'] = feature_name
with open(config_file, 'w') as f:
    json.dump(data, f, indent=2)
" "$config_file" "$worktree_base" "$feature_name"
    fi
  else
    if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
      echo "エラー: jq または python3 が必要です" >&2; exit 1
    fi
    # jq/python3 非存在でもJSON特殊文字を安全にエスケープするためpython3を使用
    python3 -c "
import json, sys
data = {'worktreeDir': sys.argv[1]}
if sys.argv[2]:
    data['featureName'] = sys.argv[2]
with open(sys.argv[3], 'w') as f:
    json.dump(data, f, indent=2)
print()
" "$worktree_base" "$feature_name" "$config_file"
  fi
  echo "✓ project-config.json に worktreeDir を記録しました"
}

cmd_create_task() {
  local worktree_base="${1:?エラー: worktree_base が必要です}"
  local agent_name="${2:?エラー: agent_name が必要です}"
  local branch_name="${3:?エラー: branch_name が必要です}"
  local parent_branch="${4:?エラー: parent_branch が必要です}"

  local worktree_path="${worktree_base}/${agent_name}"

  if [[ -d "$worktree_path" ]]; then
    git worktree remove --force "$worktree_path" 2>/dev/null || true
    echo "既存worktreeを削除しました: $worktree_path"
  fi

  # branch_name に既に feature/ が含まれる場合は二重付与を防止
  local full_branch_name
  if [[ "$branch_name" == feature/* ]]; then
    full_branch_name="$branch_name"
  else
    full_branch_name="feature/${branch_name}"
  fi

  if git rev-parse --verify "$full_branch_name" >/dev/null 2>&1; then
    git worktree add "$worktree_path" "$full_branch_name"
  else
    git worktree add "$worktree_path" -b "$full_branch_name" "$parent_branch"
  fi
  echo "✓ タスク用worktreeを作成しました: $worktree_path"
  echo "$worktree_path"
}

cmd_setup_symlinks() {
  local project_dir="${1:?エラー: project_dir が必要です}"
  local worktree_path="${2:?エラー: worktree_path が必要です}"

  # symlink対象（dist/build/は除外 — 並列ビルドで上書き競合するため）
  local symlink_targets=("node_modules" ".venv" "vendor")

  # pnpm non-hoisted → node_modules除外（事前チェック）
  if [[ -f "${project_dir}/.npmrc" ]] \
    && grep -qE "node-linker\s*=\s*(pnp|isolated)" "${project_dir}/.npmrc" 2>/dev/null; then
    symlink_targets=(".venv" "vendor")
    echo "⚠ pnpm non-hoisted モード検出 — node_modules symlinkスキップ"
  fi

  # Yarn PnP / pnpm mode → node_modules除外（事前チェック）
  if [[ -f "${project_dir}/.yarnrc.yml" ]] \
    && grep -qE "nodeLinker:\s*(pnp|pnpm)" "${project_dir}/.yarnrc.yml" 2>/dev/null; then
    symlink_targets=(".venv" "vendor")
    echo "⚠ Yarn PnP/pnpm モード検出 — node_modules symlinkスキップ"
  fi

  local linked=0
  for item in "${symlink_targets[@]}"; do
    local src="${project_dir}/${item}"
    local dst="${worktree_path}/${item}"
    if [[ -d "$src" ]] && [[ ! -e "$dst" ]]; then
      ln -s "$src" "$dst"
      echo "✓ symlink作成: $dst → $src"
      linked=$((linked + 1))
    fi
  done

  if [[ $linked -eq 0 ]]; then
    echo "symlink対象のディレクトリが見つかりませんでした（worktreeでのnpm installが必要かもしれません）"
  fi
}

cmd_remove() {
  local worktree_path="${1:?エラー: worktree_path が必要です}"
  local branch_name="${2:-}"

  if git worktree remove "$worktree_path" 2>/dev/null; then
    echo "✓ worktreeを削除しました: $worktree_path"
  else
    echo "通常の削除に失敗しました。--force で再試行します..."
    git worktree remove --force "$worktree_path"
    echo "✓ worktreeを強制削除しました: $worktree_path"
  fi

  if [[ -n "$branch_name" ]]; then
    if git branch -d "feature/${branch_name}" 2>/dev/null; then
      echo "✓ ブランチを削除しました: feature/${branch_name}"
    else
      git branch -D "feature/${branch_name}" 2>/dev/null || true
      echo "✓ ブランチを強制削除しました: feature/${branch_name}"
    fi
  fi
}

cmd_list() {
  local worktree_base="${1:-}"

  if [[ -n "$worktree_base" ]]; then
    git worktree list | grep -F "$worktree_base" || echo "指定ベースディレクトリ配下にworktreeはありません: $worktree_base"
  else
    git worktree list
  fi
}

cmd_cleanup() {
  local worktree_base="${1:?エラー: worktree_base が必要です}"

  # M8: 空ディレクトリのglobが展開されないケースを防止
  shopt -s nullglob

  if [[ -d "$worktree_base" ]]; then
    for wt_dir in "$worktree_base"/*/; do
      if [[ -d "$wt_dir" ]]; then
        local wt_path
        wt_path=$(cd "$wt_dir" && pwd)

        # M7: このworktreeに対応するブランチを削除前に記録
        local wt_branch=""
        wt_branch=$(git worktree list --porcelain | awk -v p="$wt_path" '
          /^worktree/ { in_wt = ($2 == p) }
          /^branch/ && in_wt { sub("refs/heads/", "", $2); print $2; in_wt=0 }
        ' 2>/dev/null || true)

        if git worktree remove "$wt_path" 2>/dev/null; then
          echo "✓ worktreeを削除しました: $wt_path"
        else
          git worktree remove --force "$wt_path" 2>/dev/null || true
          echo "✓ worktreeを強制削除しました: $wt_path"
        fi

        # M7: worktreeに対応するブランチのみ削除（他featureブランチに影響しない）
        if [[ -n "$wt_branch" ]]; then
          if git branch -d "$wt_branch" 2>/dev/null; then
            echo "✓ ブランチを削除しました: $wt_branch"
          else
            git branch -D "$wt_branch" 2>/dev/null || true
            echo "✓ ブランチを強制削除しました: $wt_branch"
          fi
        fi
      fi
    done
  fi

  if [[ -d "$worktree_base" ]]; then
    rm -rf "$worktree_base"
    echo "✓ worktreeベースディレクトリを削除しました: $worktree_base"
  fi

  shopt -u nullglob

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
    gitdir=$(sed 's/^gitdir: //' "$git_file")
    if [[ ! -d "$gitdir" ]]; then
      echo "警告: .gitファイルが指すディレクトリが存在しません: $gitdir"
      echo "git worktree repair を実行します..."
    fi
  fi

  git worktree repair
  echo "✓ worktreeの修復が完了しました: $worktree_path"
}

if [[ $# -lt 1 ]]; then
  usage
fi

subcommand="$1"
shift

case "$subcommand" in
  create-parent)   cmd_create_parent "$@" ;;
  create-task)     cmd_create_task "$@" ;;
  setup-symlinks)  cmd_setup_symlinks "$@" ;;
  remove)          cmd_remove "$@" ;;
  list)            cmd_list "$@" ;;
  cleanup)         cmd_cleanup "$@" ;;
  resolve-gitdir)  cmd_resolve_gitdir "$@" ;;
  *)
    echo "エラー: 不明なサブコマンド: $subcommand"
    usage
    ;;
esac
