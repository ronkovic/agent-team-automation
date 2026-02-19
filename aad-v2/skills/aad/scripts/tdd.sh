#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
使用方法: $(basename "$0") <サブコマンド> [引数...]

サブコマンド:
  detect-framework [<project_dir>]                テストフレームワークを検出
  run-tests [<project_dir>]                       テストを実行
  commit-phase <phase> <scope> <description> [<worktree_path>]  TDDフェーズのコミット
  merge-to-parent <worktree_path> <agent_name> <parent_branch> <project_dir>  親ブランチへマージ
EOF
  exit 1
}

cmd_detect_framework() {
  local project_dir="${1:-.}"

  # 1. bun
  if [[ -f "${project_dir}/bun.lockb" ]]; then
    echo "bun"
    return
  fi
  if [[ -f "${project_dir}/package.json" ]] && \
     grep -qE '"packageManager"\s*:\s*"bun|"test"\s*:\s*"bun\s' "${project_dir}/package.json" 2>/dev/null; then
    echo "bun"
    return
  fi

  # 2. vitest
  if [[ -f "${project_dir}/package.json" ]] && grep -q '"vitest"' "${project_dir}/package.json" 2>/dev/null; then
    echo "vitest"
    return
  fi

  # 3. jest
  if [[ -f "${project_dir}/package.json" ]] && grep -q '"jest"' "${project_dir}/package.json" 2>/dev/null; then
    echo "jest"
    return
  fi

  # 4. pytest
  if [[ -f "${project_dir}/pyproject.toml" ]] || [[ -f "${project_dir}/setup.py" ]] || [[ -f "${project_dir}/requirements.txt" ]]; then
    echo "pytest"
    return
  fi

  # 5. go-test
  if [[ -f "${project_dir}/go.mod" ]]; then
    echo "go-test"
    return
  fi

  # 6. cargo
  if [[ -f "${project_dir}/Cargo.toml" ]]; then
    echo "cargo"
    return
  fi

  echo "unknown"
}

cmd_run_tests() {
  local project_dir="${1:-.}"
  local framework
  framework=$(cmd_detect_framework "$project_dir")

  echo "検出されたフレームワーク: $framework"
  cd "$project_dir"

  case "$framework" in
    bun)
      bun test
      ;;
    vitest)
      npx vitest run
      ;;
    jest)
      npx jest
      ;;
    pytest)
      ${AAD_PYTHON:-python3} -m pytest
      ;;
    go-test)
      go test ./...
      ;;
    cargo)
      cargo test
      ;;
    unknown)
      echo "テストフレームワーク未検出"
      if [[ "${AAD_STRICT_TDD:-false}" == "true" ]]; then
        echo "エラー: AAD_STRICT_TDD=true ですがテストフレームワークが未検出です" >&2
        exit 1
      fi
      exit 0
      ;;
  esac
}

cmd_commit_phase() {
  local phase="${1:?エラー: phase (red/green/review) が必要です}"
  local scope="${2:?エラー: scope が必要です}"
  local description="${3:?エラー: description が必要です}"
  local worktree_path="${4:-}"

  # worktree_pathが指定されていたらそのディレクトリで実行
  if [[ -n "$worktree_path" ]]; then
    cd "$worktree_path"
  fi

  # phaseに応じたprefixを決定
  local prefix
  case "$phase" in
    red)
      prefix="test"
      ;;
    green)
      prefix="feat"
      ;;
    review|refactor)
      # C5修正: subagent-prompt.md の REFACTOR フェーズに対応
      prefix="refactor"
      ;;
    *)
      echo "エラー: 不正なphase: $phase (red/green/refactor/review のいずれかを指定してください)"
      exit 1
      ;;
  esac

  # AAD_STRICT_TDD: GREEN コミット時に直前の RED コミットの存在を確認
  if [[ "${AAD_STRICT_TDD:-false}" == "true" ]] && [[ "$phase" == "green" ]]; then
    local last_commit_msg
    last_commit_msg=$(git log -1 --format="%s" 2>/dev/null || echo "")
    if ! echo "$last_commit_msg" | grep -q "^test("; then
      echo "エラー: AAD_STRICT_TDD=true: GREEN コミットの前に RED (test) コミットが必要です" >&2
      echo "  最後のコミット: $last_commit_msg" >&2
      exit 1
    fi
  fi

  # AAD_STRICT_TDD: REFACTOR コミット時にテストが通ることを確認
  if [[ "${AAD_STRICT_TDD:-false}" == "true" ]] && [[ "$phase" == "refactor" || "$phase" == "review" ]]; then
    local framework
    framework=$(cmd_detect_framework "$(pwd)")
    if [[ "$framework" != "unknown" ]]; then
      echo "AAD_STRICT_TDD: REFACTOR前のテスト実行中..." >&2
      if ! cmd_run_tests "$(pwd)" >/dev/null 2>&1; then
        echo "エラー: AAD_STRICT_TDD=true: REFACTOR コミットの前にテストが通る必要があります" >&2
        exit 1
      fi
    fi
  fi

  # .claude/ディレクトリを除いてgit add
  git add -A -- ':!.claude/'

  # コミット
  local commit_message="${prefix}(${scope}): ${description}"
  git commit -m "$commit_message"
  echo "✓ コミットしました: $commit_message"
}

cmd_merge_to_parent() {
  local worktree_path="${1:?エラー: worktree_path が必要です}"
  local agent_name="${2:?エラー: agent_name が必要です}"
  local parent_branch="${3:?エラー: parent_branch が必要です}"
  local project_dir="${4:?エラー: project_dir が必要です}"

  local lock_file="${project_dir}/.claude/aad/aad-merge.lock"
  local timeout=120
  local elapsed=0

  # ロックディレクトリの作成
  mkdir -p "$(dirname "$lock_file")"

  # スピンロックでロックを取得
  echo "マージロックを取得中..."
  while ! (set -o noclobber; echo "$$" > "$lock_file") 2>/dev/null; do
    # stale lock検出: ロックを保持するプロセスが存在しない場合は削除
    if [[ -f "$lock_file" ]]; then
      local lock_pid
      lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
      if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
        echo "スタールロックを検出しました (PID: $lock_pid)。削除して再試行します..."
        rm -f "$lock_file"
        continue
      fi
    fi
    if [[ $elapsed -ge $timeout ]]; then
      echo "エラー: マージロックの取得がタイムアウトしました (${timeout}秒)"
      exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo "✓ マージロックを取得しました"

  # ロック解放用trapを設定
  trap 'git -C "$project_dir" merge --abort 2>/dev/null || true; rm -f "$lock_file"' EXIT

  # マージ実行
  cd "$project_dir"
  git checkout "$parent_branch"

  # feature/ 二重プレフィックス防止（worktree.sh cmd_create_task と同じガード）
  case "$agent_name" in feature/*) ;; *) agent_name="feature/${agent_name}" ;; esac

  if git merge --no-ff "${agent_name}" -m "merge(wave): merge ${agent_name}"; then
    echo "✓ マージが成功しました: ${agent_name} → ${parent_branch}"
    rm -f "$lock_file"
    trap - EXIT
  else
    # コンフリクト処理
    echo "マージコンフリクトが発生しました"

    # ロックファイル自体のコンフリクトは --theirs で自動解決
    if git diff --name-only --diff-filter=U | grep -q "\.claude/aad/aad-merge.lock"; then
      git checkout --theirs "$lock_file" 2>/dev/null || true
      git add "$lock_file" 2>/dev/null || true
      echo "ロックファイルのコンフリクトを自動解決しました"
    fi

    # その他のコンフリクトがあるかチェック
    local remaining_conflicts
    remaining_conflicts=$(git diff --name-only --diff-filter=U | grep -v "\.claude/aad/aad-merge.lock" || true)
    if [[ -n "$remaining_conflicts" ]]; then
      echo "エラー: 以下のファイルにコンフリクトがあります:"
      echo "$remaining_conflicts"
      git merge --abort 2>/dev/null || true
      rm -f "$lock_file"
      trap - EXIT
      exit 1
    fi

    # H1修正: ロックファイルのみのコンフリクトを解決した場合、マージコミットを実行
    git commit --no-edit -m "merge(wave): merge ${agent_name} (auto-resolved lock conflict)"
    echo "✓ マージが完了しました (ロックファイルのコンフリクトを自動解決): ${agent_name} → ${parent_branch}"
    rm -f "$lock_file"
    trap - EXIT
  fi
}

# メインエントリポイント
if [[ $# -lt 1 ]]; then
  usage
fi

subcommand="$1"
shift

case "$subcommand" in
  detect-framework) cmd_detect_framework "$@" ;;
  run-tests)        cmd_run_tests "$@" ;;
  commit-phase)     cmd_commit_phase "$@" ;;
  merge-to-parent)  cmd_merge_to_parent "$@" ;;
  *)
    echo "エラー: 不明なサブコマンド: $subcommand"
    usage
    ;;
esac
