#!/usr/bin/env bash
# test_aad_scripts.sh — aad-v2 スクリプト実行テスト (23ケース)
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/aad-v2/skills/aad/scripts" && pwd)"
TEST_DIR="/tmp/aad-test-$$"
PASS=0
FAIL=0

# ---- ユーティリティ ----
pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ FAIL: $1 — $2"; FAIL=$((FAIL+1)); }

run_test() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name" "exit code $?"
  fi
}

header() { echo; echo "=== $1 ==="; }

# ---- セットアップ ----
setup() {
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"

  # Python プロジェクト
  cat > requirements.txt <<'EOF'
pytest>=7.0
EOF
  cat > test_hello.py <<'EOF'
def test_hello():
    assert 1 + 1 == 2
EOF

  # Node.js プロジェクト
  cat > package.json <<'EOF'
{
  "name": "aad-test",
  "version": "1.0.0",
  "scripts": { "test": "echo ok" }
}
EOF

  # 初期コミット
  git add -A
  git commit -q -m "chore: initial"
}

teardown() {
  cd /tmp
  rm -rf "$TEST_DIR"
}

# ============================================================
# 1. deps.sh
# ============================================================
test_deps() {
  header "1. deps.sh"
  cd "$TEST_DIR"

  # 1-1: source + deps_install
  (
    source "${SCRIPTS_DIR}/deps.sh"
    deps_install "." 2>&1 | grep -q "Python実行環境"
  ) && pass "1-1: source + deps_install" || fail "1-1" "Python実行環境 が出力されない"

  # 1-2: 直接実行
  run_test "1-2: bash deps.sh install" bash "${SCRIPTS_DIR}/deps.sh" install "."

  # 1-3: AAD_PYTHON export 確認
  (
    source "${SCRIPTS_DIR}/deps.sh"
    deps_install "." >/dev/null 2>&1
    [[ -n "${AAD_PYTHON:-}" ]] || { echo "AAD_PYTHON is empty"; exit 1; }
  ) && pass "1-3: AAD_PYTHON 非空" || fail "1-3" "AAD_PYTHON が空"

  # 1-4: frontend npm install (npm 存在時のみ)
  # 依存なし package.json では node_modules は作成されないが package-lock.json は作成される
  if command -v npm >/dev/null 2>&1; then
    mkdir -p frontend
    echo '{"name":"fe","version":"1.0.0"}' > frontend/package.json
    bash "${SCRIPTS_DIR}/deps.sh" install "." >/dev/null 2>&1
    [[ -f "frontend/package-lock.json" ]] \
      && pass "1-4: frontend npm install 実行済み (package-lock.json 存在)" \
      || fail "1-4" "frontend/package-lock.json が作成されない"
    rm -rf frontend
  else
    pass "1-4: npm 未検出のためスキップ"
  fi
}

# ============================================================
# 2. plan.sh
# ============================================================
test_plan() {
  header "2. plan.sh"
  cd "$TEST_DIR"

  # 2-1: init JSON 出力
  local init_json
  init_json=$(bash "${SCRIPTS_DIR}/plan.sh" init "." 2>/dev/null)
  if command -v jq >/dev/null 2>&1; then
    echo "$init_json" | jq -e '.runId and .projectDir and .projectName and .language and .currentBranch' >/dev/null \
      && pass "2-1: init JSON (jq検証)" || fail "2-1" "jq検証失敗: $init_json"
  else
    echo "$init_json" | python3 -c "import json,sys; d=json.load(sys.stdin); assert all(k in d for k in ['runId','projectDir','projectName','language','currentBranch'])" \
      && pass "2-1: init JSON (python3検証)" || fail "2-1" "python3検証失敗"
  fi

  # 2-2: validate 正常 plan.json
  local valid_plan="${TEST_DIR}/valid_plan.json"
  cat > "$valid_plan" <<'EOF'
{
  "featureName": "test",
  "waves": [
    {
      "id": 1, "type": "parallel",
      "agents": [
        {"name": "agent-a", "model": "sonnet", "tasks": ["task1"], "files": ["a.py"], "dependsOn": []}
      ]
    }
  ]
}
EOF
  bash "${SCRIPTS_DIR}/plan.sh" validate "$valid_plan" 2>&1 | grep -q "validation passed" \
    && pass "2-2: validate 正常" || fail "2-2" "validation passed が出力されない"

  # 2-3: validate 重複 ID
  local dup_plan="${TEST_DIR}/dup_plan.json"
  cat > "$dup_plan" <<'EOF'
{
  "featureName": "test",
  "waves": [
    {
      "id": 1, "type": "parallel",
      "agents": [
        {"name": "agent-a", "tasks": [], "files": [], "dependsOn": []},
        {"name": "agent-a", "tasks": [], "files": [], "dependsOn": []}
      ]
    }
  ]
}
EOF
  if ! bash "${SCRIPTS_DIR}/plan.sh" validate "$dup_plan" >/dev/null 2>&1; then
    pass "2-3: validate 重複ID → exit 1"
  else
    fail "2-3" "exit 0 が返った (重複を検出すべき)"
  fi

  # 2-4: validate 不正依存
  local dep_plan="${TEST_DIR}/dep_plan.json"
  cat > "$dep_plan" <<'EOF'
{
  "featureName": "test",
  "waves": [
    {
      "id": 1, "type": "parallel",
      "agents": [
        {"name": "agent-a", "tasks": [], "files": [], "dependsOn": ["nonexistent"]}
      ]
    }
  ]
}
EOF
  if ! bash "${SCRIPTS_DIR}/plan.sh" validate "$dep_plan" >/dev/null 2>&1; then
    pass "2-4: validate 不正依存 → exit 1"
  else
    fail "2-4" "exit 0 が返った (不正依存を検出すべき)"
  fi
}

# ============================================================
# 3. worktree.sh
# ============================================================
test_worktree() {
  header "3. worktree.sh"
  cd "$TEST_DIR"

  local PARENT="aad/develop"
  local WT_BASE="${TEST_DIR}-test-wt"

  # 3-1: create-parent
  bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$TEST_DIR" "$PARENT" "test" >/dev/null 2>&1
  [[ -d "$WT_BASE" ]] && pass "3-1: create-parent → ベースdir" || fail "3-1" "ベースdir が作成されない"
  git -C "$TEST_DIR" rev-parse --verify "$PARENT" >/dev/null 2>&1 \
    && pass "3-1b: create-parent → ブランチ" || fail "3-1b" "ブランチが作成されない"
  [[ -f "${TEST_DIR}/.claude/aad/project-config.json" ]] \
    && pass "3-1c: create-parent → config.json" || fail "3-1c" "config.json が作成されない"

  # 3-2: create-task worker-1
  git -C "$TEST_DIR" checkout -q "$PARENT"
  bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_BASE" "worker-1" "worker-1" "$PARENT" >/dev/null 2>&1
  [[ -d "${WT_BASE}/worker-1" ]] \
    && pass "3-2: create-task worker-1 → worktree dir" || fail "3-2" "worktree dir が作成されない"
  git -C "$TEST_DIR" rev-parse --verify "feature/worker-1" >/dev/null 2>&1 \
    && pass "3-2b: create-task → feature ブランチ" || fail "3-2b" "feature ブランチが作成されない"

  # 3-3: create-task worker-2
  bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_BASE" "worker-2" "worker-2" "$PARENT" >/dev/null 2>&1
  [[ -d "${WT_BASE}/worker-2" ]] \
    && pass "3-3: create-task worker-2" || fail "3-3" "2つ目のworktree dir が作成されない"

  # 3-4: setup-symlinks (node_modules が存在する場合のみ有効)
  if [[ -d "${TEST_DIR}/node_modules" ]]; then
    bash "${SCRIPTS_DIR}/worktree.sh" setup-symlinks "$TEST_DIR" "${WT_BASE}/worker-1" >/dev/null 2>&1
    [[ -L "${WT_BASE}/worker-1/node_modules" ]] \
      && pass "3-4: setup-symlinks → node_modules symlink" || fail "3-4" "symlink が作成されない"
  else
    pass "3-4: node_modules 未存在のためスキップ"
  fi

  # 3-5: list
  bash "${SCRIPTS_DIR}/worktree.sh" list "$WT_BASE" 2>/dev/null | grep -q "worker-1" \
    && pass "3-5: list → worker-1 表示" || fail "3-5" "worker-1 が表示されない"

  # 3-6: remove worker-2
  bash "${SCRIPTS_DIR}/worktree.sh" remove "${WT_BASE}/worker-2" "worker-2" >/dev/null 2>&1
  [[ ! -d "${WT_BASE}/worker-2" ]] \
    && pass "3-6: remove worker-2 → dir 削除" || fail "3-6" "dir が残っている"
  ! git -C "$TEST_DIR" rev-parse --verify "feature/worker-2" >/dev/null 2>&1 \
    && pass "3-6b: remove → ブランチ削除" || fail "3-6b" "ブランチが残っている"

  # 3-7: worker-1 が残っていることを確認
  [[ -d "${WT_BASE}/worker-1" ]] \
    && pass "3-7: worker-1 は影響を受けない" || fail "3-7" "worker-1 が削除された"

  # クリーンアップ
  bash "${SCRIPTS_DIR}/worktree.sh" cleanup "$WT_BASE" >/dev/null 2>&1 || true
}

# ============================================================
# 4. tdd.sh
# ============================================================
test_tdd() {
  header "4. tdd.sh"
  cd "$TEST_DIR"
  git checkout -q main 2>/dev/null || git checkout -q "$(git rev-parse --abbrev-ref HEAD)"

  # 4-1: detect-framework (jest)
  local saved_pkg
  saved_pkg=$(cat package.json)
  echo '{"name":"t","devDependencies":{"jest":"^29"}}' > package.json
  local fw
  fw=$(bash "${SCRIPTS_DIR}/tdd.sh" detect-framework "." 2>/dev/null)
  [[ "$fw" == "jest" ]] && pass "4-1: detect-framework jest" || fail "4-1" "got: $fw"
  echo "$saved_pkg" > package.json

  # 4-2: detect-framework (pytest)
  fw=$(bash "${SCRIPTS_DIR}/tdd.sh" detect-framework "." 2>/dev/null)
  [[ "$fw" == "pytest" ]] && pass "4-2: detect-framework pytest" || fail "4-2" "got: $fw"

  # 4-3: detect-framework (empty dir)
  local empty_dir="${TEST_DIR}/empty_fw"
  mkdir -p "$empty_dir"
  git -C "$empty_dir" init -q 2>/dev/null || true
  fw=$(bash "${SCRIPTS_DIR}/tdd.sh" detect-framework "$empty_dir" 2>/dev/null)
  [[ "$fw" == "unknown" ]] && pass "4-3: detect-framework empty → unknown" || fail "4-3" "got: $fw"
  rm -rf "$empty_dir"

  # 4-4: commit-phase (red/green/review prefix チェック)
  git -C "$TEST_DIR" checkout -q main 2>/dev/null || true
  for phase in red green review; do
    local prefix
    case "$phase" in
      red)    prefix="test" ;;
      green)  prefix="feat" ;;
      review) prefix="refactor" ;;
    esac
    echo "$phase-change" >> "${TEST_DIR}/test_hello.py"
    git -C "$TEST_DIR" add -A >/dev/null 2>&1
    bash "${SCRIPTS_DIR}/tdd.sh" commit-phase "$phase" "core" "test commit" "$TEST_DIR" >/dev/null 2>&1
    local last_msg
    last_msg=$(git -C "$TEST_DIR" log -1 --format="%s")
    [[ "$last_msg" == "${prefix}(core): test commit" ]] \
      && pass "4-4: commit-phase $phase → prefix=$prefix" \
      || fail "4-4" "phase=$phase got: $last_msg"
  done

  # 4-5: merge-to-parent (スピンロック + マージ)
  local parent_b="aad/develop"
  git -C "$TEST_DIR" branch -f "$parent_b" HEAD 2>/dev/null || true
  git -C "$TEST_DIR" checkout -q "$parent_b"
  git -C "$TEST_DIR" checkout -b "feature/merge-test" >/dev/null 2>&1
  echo "merge-test-file" > "${TEST_DIR}/merge_test.txt"
  git -C "$TEST_DIR" add -A && git -C "$TEST_DIR" commit -q -m "feat: merge test"
  git -C "$TEST_DIR" checkout -q "$parent_b"

  bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$TEST_DIR" "merge-test" "$parent_b" "$TEST_DIR" >/dev/null 2>&1
  [[ -f "${TEST_DIR}/merge_test.txt" ]] \
    && pass "4-5: merge-to-parent → マージ成功" || fail "4-5" "merge_test.txt が存在しない"

  git -C "$TEST_DIR" branch -D "feature/merge-test" >/dev/null 2>&1 || true
}

# ============================================================
# 5. cleanup.sh
# ============================================================
test_cleanup() {
  header "5. cleanup.sh"
  cd "$TEST_DIR"

  # cleanup.sh には project-config.json が必要
  local PARENT="aad/develop"
  local WT_BASE="${TEST_DIR}-cleanup-wt"
  mkdir -p "$WT_BASE"

  git -C "$TEST_DIR" checkout -q "$PARENT" 2>/dev/null \
    || git -C "$TEST_DIR" checkout -b "$PARENT" >/dev/null 2>&1

  # worktree 作成
  bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_BASE" "cl-worker" "cl-worker" "$PARENT" >/dev/null 2>&1

  # project-config.json 設定
  mkdir -p "${TEST_DIR}/.claude/aad"
  python3 -c "
import json, sys
json.dump({'worktreeDir': sys.argv[1], 'parentBranch': sys.argv[2]}, open(sys.argv[3], 'w'), indent=2)
" "$WT_BASE" "$PARENT" "${TEST_DIR}/.claude/aad/project-config.json"

  # state.json 作成
  echo '{"runId":"test","tasks":{}}' > "${TEST_DIR}/.claude/aad/state.json"

  # 5-1: run
  bash "${SCRIPTS_DIR}/cleanup.sh" run "$TEST_DIR" >/dev/null 2>&1
  [[ ! -d "$WT_BASE" ]] \
    && pass "5-1: cleanup run → worktree 削除" || fail "5-1" "worktree が残っている"
  [[ -f "${TEST_DIR}/.claude/aad/state.json" ]] \
    && pass "5-1b: cleanup run → state.json は残る" || fail "5-1b" "state.json が削除された"
  ls "${TEST_DIR}/.claude/aad/archive/" >/dev/null 2>&1 \
    && pass "5-1c: cleanup run → archive 作成" || fail "5-1c" "archive が作成されない"

  # 5-2: orphans (正常終了 + git worktree prune が実行されることを確認)
  local orphan_out
  orphan_out=$(bash "${SCRIPTS_DIR}/cleanup.sh" orphans "$TEST_DIR" 2>&1)
  if echo "$orphan_out" | grep -q "prune"; then
    pass "5-2: orphans → git worktree prune 実行"
  else
    fail "5-2" "prune メッセージなし。実際の出力: $orphan_out"
  fi

  # 5-3: orphans でマージ済みブランチ処理（エラーなし完了）
  bash "${SCRIPTS_DIR}/cleanup.sh" orphans "$TEST_DIR" >/dev/null 2>&1 \
    && pass "5-3: orphans 正常完了" || fail "5-3" "exit code != 0"
}

# ============================================================
# メイン
# ============================================================
main() {
  echo "=============================="
  echo " AAD v2 スクリプトテスト"
  echo " SCRIPTS_DIR: $SCRIPTS_DIR"
  echo "=============================="

  setup
  trap teardown EXIT

  test_deps
  test_plan
  test_worktree
  test_tdd
  test_cleanup

  echo
  echo "=============================="
  echo " 結果: PASS=${PASS} FAIL=${FAIL}"
  echo "=============================="

  [[ $FAIL -eq 0 ]] && exit 0 || exit 1
}

main
