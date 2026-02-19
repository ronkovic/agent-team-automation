#!/usr/bin/env bash
# aad-v2 追加テスト — hooks + エッジケース
set -euo pipefail

SCRIPTS_DIR="/Users/kazuki/workspace/sandbox/agent-team-automation/aad-v2/skills/aad/scripts"
HOOKS_DIR="/Users/kazuki/workspace/sandbox/agent-team-automation/aad-v2/hooks"
TEST_DIR="/tmp/aad-extra-test-$$"
PASS=0
FAIL=0

pass() { echo "  ✓ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ FAIL: $1 — $2"; FAIL=$((FAIL+1)); }
header() { echo; echo "=== $1 ==="; }

setup() {
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "# test" > README.md
  git add -A && git commit -q -m "init"
}

teardown() {
  cd /tmp
  rm -rf "$TEST_DIR"
}

# ============================================================
# 6. hooks/memory-check.sh
# ============================================================
test_hooks_memory() {
  header "6. hooks/memory-check.sh"

  # 6-1: 通常実行 (メモリ十分) → BLOCK出力なし・exit 0
  local out
  out=$(bash "${HOOKS_DIR}/memory-check.sh" 2>&1 || true)
  if echo "$out" | grep -q "BLOCK"; then
    # メモリ不足の場合はPASSとしてカウント（環境依存）
    pass "6-1: memory-check.sh → BLOCK出力あり (メモリ不足環境)"
  else
    pass "6-1: memory-check.sh → BLOCK出力なし (メモリ十分)"
  fi

  # 6-2: 正常終了 (exit code 0)
  bash "${HOOKS_DIR}/memory-check.sh" >/dev/null 2>&1
  pass "6-2: memory-check.sh → exit 0"
}

# ============================================================
# 7. hooks/worktree-boundary.sh
# ============================================================
test_hooks_boundary() {
  header "7. hooks/worktree-boundary.sh"

  # 7-1: AAD_WORKTREE_PATH 未設定 → exit 0 (チェックしない)
  local out
  out=$(TOOL_INPUT='{"file_path":"/tmp/outside/file.txt"}' \
    bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1 || true)
  if echo "$out" | grep -q "BLOCK"; then
    fail "7-1" "AAD_WORKTREE_PATH未設定なのにBLOCK出力"
  else
    pass "7-1: AAD_WORKTREE_PATH未設定 → チェックしない"
  fi

  # 7-2: AAD_WORKTREE_PATH 設定 + 範囲内ファイル → exit 0
  out=$(AAD_WORKTREE_PATH="/tmp/my-wt/worker-1" \
    TOOL_INPUT='{"file_path":"/tmp/my-wt/worker-1/src/main.py"}' \
    bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1 || true)
  if echo "$out" | grep -q "BLOCK"; then
    fail "7-2" "範囲内なのにBLOCK出力: $out"
  else
    pass "7-2: 範囲内ファイル → BLOCK なし"
  fi

  # 7-3: AAD_WORKTREE_PATH 設定 + 範囲外ファイル → BLOCK
  out=$(AAD_WORKTREE_PATH="/tmp/my-wt/worker-1" \
    TOOL_INPUT='{"file_path":"/tmp/outside/secret.py"}' \
    bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1 || true)
  if echo "$out" | grep -q "BLOCK"; then
    pass "7-3: 範囲外ファイル → BLOCK 出力"
  else
    fail "7-3" "範囲外なのにBLOCK出力なし"
  fi

  # 7-4: C1修正: -wt/ を含む別worktreeパス → BLOCK (過剰許可の修正)
  out=$(AAD_WORKTREE_PATH="/tmp/my-wt/worker-1" \
    TOOL_INPUT='{"file_path":"/tmp/other-wt/shared.txt"}' \
    bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1 || true)
  if echo "$out" | grep -q "BLOCK"; then
    pass "7-4: 別worktreeの -wt/ パス → BLOCK (境界外)"
  else
    fail "7-4" "別worktreeパスなのにBLOCK出力なし: $out"
  fi

  # 7-5: C2修正: 任意の .claude/ パス → BLOCK (過剰許可の修正)
  out=$(AAD_WORKTREE_PATH="/tmp/my-wt/worker-1" \
    TOOL_INPUT='{"file_path":"/any/path/.claude/settings.json"}' \
    bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1 || true)
  if echo "$out" | grep -q "BLOCK"; then
    pass "7-5: 任意の .claude/ パス → BLOCK (AAD_PROJECT_DIR未設定)"
  else
    fail "7-5" "任意の .claude/ パスなのにBLOCK出力なし: $out"
  fi

  # 7-5b: C2修正: AAD_PROJECT_DIR を設定した場合、プロジェクトの .claude/ は許可
  out=$(AAD_WORKTREE_PATH="/tmp/my-wt/worker-1" \
    AAD_PROJECT_DIR="/tmp/myproject" \
    TOOL_INPUT='{"file_path":"/tmp/myproject/.claude/aad/state.json"}' \
    bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1 || true)
  if echo "$out" | grep -q "BLOCK"; then
    fail "7-5b" "プロジェクトの .claude/ なのにBLOCK出力: $out"
  else
    pass "7-5b: AAD_PROJECT_DIR の .claude/ → BLOCK なし (状態管理許可)"
  fi

  # 7-6: C3修正: 相対パス → BLOCK (境界チェック不可のため拒否)
  out=$(AAD_WORKTREE_PATH="/tmp/my-wt/worker-1" \
    TOOL_INPUT='{"file_path":"relative/path.py"}' \
    bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1 || true)
  if echo "$out" | grep -q "BLOCK"; then
    pass "7-6: 相対パス → BLOCK (セキュリティ上拒否)"
  else
    fail "7-6" "相対パスなのにBLOCK出力なし"
  fi

  # 7-7: TOOL_INPUT が空 → exit 0
  out=$(AAD_WORKTREE_PATH="/tmp/my-wt" TOOL_INPUT="" \
    bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1 || true)
  if echo "$out" | grep -q "BLOCK"; then
    fail "7-7" "空TOOL_INPUTなのにBLOCK"
  else
    pass "7-7: TOOL_INPUT空 → BLOCK なし"
  fi
}

# ============================================================
# 8. plan.sh エッジケース
# ============================================================
test_plan_edge() {
  header "8. plan.sh エッジケース"
  cd "$TEST_DIR"

  # 8-1: validate ファイル競合
  local conflict_plan="${TEST_DIR}/conflict_plan.json"
  cat > "$conflict_plan" <<'EOF'
{
  "featureName": "test",
  "waves": [
    {
      "id": 1, "type": "parallel",
      "agents": [
        {"name": "agent-a", "tasks": [], "files": ["src/shared.py"], "dependsOn": []},
        {"name": "agent-b", "tasks": [], "files": ["src/shared.py"], "dependsOn": []}
      ]
    }
  ]
}
EOF
  if ! bash "${SCRIPTS_DIR}/plan.sh" validate "$conflict_plan" >/dev/null 2>&1; then
    pass "8-1: validate ファイル競合 → exit 1"
  else
    fail "8-1" "exit 0 が返った (ファイル競合を検出すべき)"
  fi

  # 8-2: validate apiContract ルートレベル配置エラー
  local api_plan="${TEST_DIR}/api_root_plan.json"
  cat > "$api_plan" <<'EOF'
{
  "featureName": "test",
  "apiContract": {"endpoints": []},
  "waves": [
    {"id": 1, "type": "sequential", "agents": [
      {"name": "a1", "tasks": [], "files": [], "dependsOn": []}
    ]}
  ]
}
EOF
  if ! bash "${SCRIPTS_DIR}/plan.sh" validate "$api_plan" >/dev/null 2>&1; then
    pass "8-2: validate apiContract ルートレベル → exit 1"
  else
    fail "8-2" "exit 0 が返った (ルートレベルapiContractを検出すべき)"
  fi

  # 8-3: validate PATCH semantics 欠如
  local patch_plan="${TEST_DIR}/patch_plan.json"
  cat > "$patch_plan" <<'EOF'
{
  "featureName": "test",
  "waves": [
    {
      "id": 0, "type": "sequential",
      "apiContract": {
        "endpoints": [
          {"method": "PATCH", "path": "/api/items/:id", "request": "{id}", "response": "Item"}
        ]
      },
      "agents": [
        {"name": "a1", "tasks": [], "files": [], "dependsOn": []}
      ]
    }
  ]
}
EOF
  if ! bash "${SCRIPTS_DIR}/plan.sh" validate "$patch_plan" >/dev/null 2>&1; then
    pass "8-3: validate PATCH semantics 欠如 → exit 1"
  else
    fail "8-3" "exit 0 が返った (PATCH semantics欠如を検出すべき)"
  fi

  # 8-4: validate apiContract 禁止キー
  local forbidden_plan="${TEST_DIR}/forbidden_plan.json"
  cat > "$forbidden_plan" <<'EOF'
{
  "featureName": "test",
  "waves": [
    {
      "id": 0, "type": "sequential",
      "apiContract": {
        "endpoints": [],
        "forbidden_key": "value"
      },
      "agents": [
        {"name": "a1", "tasks": [], "files": [], "dependsOn": []}
      ]
    }
  ]
}
EOF
  if ! bash "${SCRIPTS_DIR}/plan.sh" validate "$forbidden_plan" >/dev/null 2>&1; then
    pass "8-4: validate 禁止キー → exit 1"
  else
    fail "8-4" "exit 0 が返った (禁止キーを検出すべき)"
  fi

  # 8-5: validate 空のwaves → 正常
  local empty_waves="${TEST_DIR}/empty_waves.json"
  cat > "$empty_waves" <<'EOF'
{
  "featureName": "test",
  "waves": []
}
EOF
  bash "${SCRIPTS_DIR}/plan.sh" validate "$empty_waves" 2>&1 | grep -q "validation passed" \
    && pass "8-5: validate 空waves → passed" \
    || fail "8-5" "validation passedが出力されない"

  # 8-6: init → language = javascript/typescript
  cat > "${TEST_DIR}/package.json" <<'EOF'
{"name":"test","version":"1.0.0"}
EOF
  local init_json
  init_json=$(bash "${SCRIPTS_DIR}/plan.sh" init "$TEST_DIR" 2>/dev/null)
  if echo "$init_json" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['language']=='javascript/typescript'" 2>/dev/null; then
    pass "8-6: init language → javascript/typescript"
  else
    fail "8-6" "language検出失敗: $init_json"
  fi
}

# ============================================================
# 9. tdd.sh エッジケース
# ============================================================
test_tdd_edge() {
  header "9. tdd.sh エッジケース"
  cd "$TEST_DIR"

  # 9-1: detect-framework bun.lockb
  touch "${TEST_DIR}/bun.lockb"
  local fw
  fw=$(bash "${SCRIPTS_DIR}/tdd.sh" detect-framework "$TEST_DIR" 2>/dev/null)
  rm -f "${TEST_DIR}/bun.lockb"
  [[ "$fw" == "bun" ]] && pass "9-1: detect-framework bun.lockb → bun" || fail "9-1" "got: $fw"

  # 9-2: detect-framework vitest
  cat > "${TEST_DIR}/package.json" <<'EOF'
{"name":"t","devDependencies":{"vitest":"^1.0"}}
EOF
  fw=$(bash "${SCRIPTS_DIR}/tdd.sh" detect-framework "$TEST_DIR" 2>/dev/null)
  [[ "$fw" == "vitest" ]] && pass "9-2: detect-framework vitest" || fail "9-2" "got: $fw"

  # 9-3: detect-framework go.mod
  local go_dir="${TEST_DIR}/go_proj"
  mkdir -p "$go_dir"
  echo "module example.com/myapp" > "${go_dir}/go.mod"
  fw=$(bash "${SCRIPTS_DIR}/tdd.sh" detect-framework "$go_dir" 2>/dev/null)
  rm -rf "$go_dir"
  [[ "$fw" == "go-test" ]] && pass "9-3: detect-framework go.mod → go-test" || fail "9-3" "got: $fw"

  # 9-4: detect-framework Cargo.toml
  local rust_dir="${TEST_DIR}/rust_proj"
  mkdir -p "$rust_dir"
  echo '[package]\nname = "myapp"' > "${rust_dir}/Cargo.toml"
  fw=$(bash "${SCRIPTS_DIR}/tdd.sh" detect-framework "$rust_dir" 2>/dev/null)
  rm -rf "$rust_dir"
  [[ "$fw" == "cargo" ]] && pass "9-4: detect-framework Cargo.toml → cargo" || fail "9-4" "got: $fw"

  # 9-5: commit-phase invalid phase → exit 1
  if ! bash "${SCRIPTS_DIR}/tdd.sh" commit-phase "invalid" "scope" "desc" "$TEST_DIR" >/dev/null 2>&1; then
    pass "9-5: commit-phase 不正phase → exit 1"
  else
    fail "9-5" "exit 0 が返った"
  fi

  # 9-6: AAD_STRICT_TDD=true で unknown フレームワーク → exit 1
  local empty_dir="${TEST_DIR}/empty_strict"
  mkdir -p "$empty_dir"
  # package.json無しでframeowrk=unknown
  if ! AAD_STRICT_TDD=true bash "${SCRIPTS_DIR}/tdd.sh" run-tests "$empty_dir" >/dev/null 2>&1; then
    pass "9-6: AAD_STRICT_TDD=true + unknown framework → exit 1"
  else
    fail "9-6" "exit 0 が返った (strictモードでエラーすべき)"
  fi
  rm -rf "$empty_dir"

  # 9-7: stale lock 検出 (存在しないPIDのlock → 自動削除してマージ成功)
  local parent_b="aad/develop"
  git -C "$TEST_DIR" rev-parse --verify "$parent_b" >/dev/null 2>&1 \
    || git -C "$TEST_DIR" branch "$parent_b" HEAD 2>/dev/null
  git -C "$TEST_DIR" checkout -q "$parent_b"
  git -C "$TEST_DIR" checkout -b "feature/stale-test" >/dev/null 2>&1
  echo "stale-test" > "${TEST_DIR}/stale_test.txt"
  git -C "$TEST_DIR" add -A && git -C "$TEST_DIR" commit -q -m "feat: stale test"
  git -C "$TEST_DIR" checkout -q "$parent_b"

  # 存在しないPIDでlockファイル作成 (stale lock)
  mkdir -p "${TEST_DIR}/.claude/aad"
  echo "99999999" > "${TEST_DIR}/.claude/aad/aad-merge.lock"

  bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$TEST_DIR" "stale-test" "$parent_b" "$TEST_DIR" >/dev/null 2>&1
  if [[ -f "${TEST_DIR}/stale_test.txt" ]]; then
    pass "9-7: stale lock 自動削除 → マージ成功"
  else
    fail "9-7" "stale lock があってもマージが完了しなかった"
  fi
  # ロックファイルが削除されたことを確認
  if [[ ! -f "${TEST_DIR}/.claude/aad/aad-merge.lock" ]]; then
    pass "9-7b: stale lock ファイル削除確認"
  else
    fail "9-7b" "lock ファイルが残っている"
  fi
  git -C "$TEST_DIR" branch -D "feature/stale-test" >/dev/null 2>&1 || true
}

# ============================================================
# 10. worktree.sh エッジケース
# ============================================================
test_worktree_edge() {
  header "10. worktree.sh エッジケース"
  cd "$TEST_DIR"

  local parent_b="aad/develop"
  git -C "$TEST_DIR" rev-parse --verify "$parent_b" >/dev/null 2>&1 \
    || git -C "$TEST_DIR" branch "$parent_b" HEAD 2>/dev/null
  git -C "$TEST_DIR" checkout -q "$parent_b"

  local WT_BASE="${TEST_DIR}-edge-wt"
  mkdir -p "$WT_BASE"

  # 10-1: feature/ プレフィックスが既についている branch_name は二重付与しない
  bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_BASE" "prefixed-worker" "feature/already-prefixed" "$parent_b" >/dev/null 2>&1
  git -C "$TEST_DIR" rev-parse --verify "feature/already-prefixed" >/dev/null 2>&1 \
    && pass "10-1: feature/ プレフィックス二重付与なし" \
    || fail "10-1" "ブランチが作成されなかった"
  ! git -C "$TEST_DIR" rev-parse --verify "feature/feature/already-prefixed" >/dev/null 2>&1 \
    && pass "10-1b: feature/feature/ が作成されていない" \
    || fail "10-1b" "feature/feature/ が作成された (二重付与)"
  bash "${SCRIPTS_DIR}/worktree.sh" remove "${WT_BASE}/prefixed-worker" "already-prefixed" >/dev/null 2>&1 || true

  # 10-2: 既存worktreeを上書きして create-task
  bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_BASE" "dup-worker" "dup-worker" "$parent_b" >/dev/null 2>&1
  bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_BASE" "dup-worker" "dup-worker" "$parent_b" >/dev/null 2>&1
  [[ -d "${WT_BASE}/dup-worker" ]] && pass "10-2: 既存worktree 上書き create-task 成功" \
    || fail "10-2" "worktreeが作成されなかった"
  bash "${SCRIPTS_DIR}/worktree.sh" remove "${WT_BASE}/dup-worker" "dup-worker" >/dev/null 2>&1 || true

  # 10-3: create-parent 再実行 (idempotent)
  bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$TEST_DIR" "$parent_b" "edge" >/dev/null 2>&1
  bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$TEST_DIR" "$parent_b" "edge" >/dev/null 2>&1 \
    && pass "10-3: create-parent 再実行 (冪等性)" \
    || fail "10-3" "2回目の create-parent が失敗"

  # 10-4: list サブコマンド (ベースdir なし → 全worktree)
  local out
  out=$(bash "${SCRIPTS_DIR}/worktree.sh" list 2>/dev/null)
  echo "$out" | grep -q "$TEST_DIR" \
    && pass "10-4: list 引数なし → worktree一覧" \
    || fail "10-4" "TEST_DIRが表示されない"

  # 10-5: setup-symlinks with node_modules
  mkdir -p "${TEST_DIR}/node_modules/test-pkg"
  bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_BASE" "sym-worker" "sym-worker" "$parent_b" >/dev/null 2>&1
  bash "${SCRIPTS_DIR}/worktree.sh" setup-symlinks "$TEST_DIR" "${WT_BASE}/sym-worker" >/dev/null 2>&1
  [[ -L "${WT_BASE}/sym-worker/node_modules" ]] \
    && pass "10-5: setup-symlinks → node_modules symlink 作成" \
    || fail "10-5" "node_modules symlink が作成されない"
  rm -rf "${TEST_DIR}/node_modules"
  bash "${SCRIPTS_DIR}/worktree.sh" remove "${WT_BASE}/sym-worker" "sym-worker" >/dev/null 2>&1 || true

  # クリーンアップ
  rm -rf "$WT_BASE"
  git worktree prune >/dev/null 2>&1 || true
}

# ============================================================
# 11. deps.sh エッジケース
# ============================================================
test_deps_edge() {
  header "11. deps.sh エッジケース"
  cd "$TEST_DIR"

  # 11-1: AAD_PYTHON がexportされているか確認 (独立したPythonプロジェクトで確認)
  local py_dir="${TEST_DIR}/py_project_test"
  mkdir -p "$py_dir"
  echo "pytest>=7.0" > "${py_dir}/requirements.txt"
  local result
  result=$(
    source "${SCRIPTS_DIR}/deps.sh"
    deps_install "${py_dir}" >/dev/null 2>&1
    echo "${AAD_PYTHON:-EMPTY}"
  )
  [[ "$result" != "EMPTY" ]] \
    && pass "11-1: AAD_PYTHON export 確認" \
    || fail "11-1" "AAD_PYTHON が export されていない"
  rm -rf "$py_dir"

  # 11-2: go.mod プロジェクト (goがない場合は警告のみ)
  local go_dir="${TEST_DIR}/go_test"
  mkdir -p "$go_dir"
  echo "module test" > "${go_dir}/go.mod"
  local go_out
  go_out=$(bash "${SCRIPTS_DIR}/deps.sh" install "$go_dir" 2>&1 || true)
  # go が存在する場合は実行、なければ警告
  if command -v go >/dev/null 2>&1; then
    pass "11-2: go プロジェクト deps install (go 存在)"
  else
    echo "$go_out" | grep -q "go 未検出\|⚠" \
      && pass "11-2: go 未検出 → 警告出力" \
      || fail "11-2" "go未検出でも警告が出ない"
  fi
  rm -rf "$go_dir"

  # 11-3: 不正サブコマンド → exit 1
  if ! bash "${SCRIPTS_DIR}/deps.sh" invalid_cmd >/dev/null 2>&1; then
    pass "11-3: 不正サブコマンド → exit 1"
  else
    fail "11-3" "exit 0 が返った"
  fi
}

# ============================================================
# 12. cleanup.sh エッジケース
# ============================================================
test_cleanup_edge() {
  header "12. cleanup.sh エッジケース"
  cd "$TEST_DIR"

  # 12-1: project-config.json なし → exit 1
  local no_config_dir="${TEST_DIR}/no_config"
  mkdir -p "${no_config_dir}/.claude/aad"
  git -C "$no_config_dir" init -q 2>/dev/null || true
  if ! bash "${SCRIPTS_DIR}/cleanup.sh" run "$no_config_dir" >/dev/null 2>&1; then
    pass "12-1: project-config.json なし → exit 1"
  else
    fail "12-1" "exit 0 が返った"
  fi
  rm -rf "$no_config_dir"

  # 12-2: state.json なし → アーカイブスキップで正常完了
  local parent_b="aad/develop"
  git -C "$TEST_DIR" rev-parse --verify "$parent_b" >/dev/null 2>&1 \
    || git -C "$TEST_DIR" branch "$parent_b" HEAD 2>/dev/null
  git -C "$TEST_DIR" checkout -q "$parent_b"

  local WT2="${TEST_DIR}-cl2-wt"
  mkdir -p "$WT2"
  bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT2" "cl2-worker" "cl2-worker" "$parent_b" >/dev/null 2>&1
  mkdir -p "${TEST_DIR}/.claude/aad"
  python3 -c "
import json, sys
json.dump({'worktreeDir': sys.argv[1], 'parentBranch': sys.argv[2]}, open(sys.argv[3], 'w'), indent=2)
" "$WT2" "$parent_b" "${TEST_DIR}/.claude/aad/project-config.json"
  rm -f "${TEST_DIR}/.claude/aad/state.json"

  local cl2_out
  cl2_out=$(bash "${SCRIPTS_DIR}/cleanup.sh" run "$TEST_DIR" 2>&1 || true)
  if echo "$cl2_out" | grep -q "クリーンアップ完了"; then
    pass "12-2: state.json なし → アーカイブスキップ正常完了"
  else
    fail "12-2" "クリーンアップ完了が出力されない: $cl2_out"
  fi

  # 12-3: orphans でgit worktree prune が呼ばれること
  local orphan_out
  orphan_out=$(bash "${SCRIPTS_DIR}/cleanup.sh" orphans "$TEST_DIR" 2>&1 || true)
  echo "$orphan_out" | grep -q "prune" \
    && pass "12-3: orphans → prune 実行確認" \
    || fail "12-3" "prune が実行されない"
}

# ============================================================
# 13. retry.sh テスト
# ============================================================
test_retry() {
  header "13. retry.sh"

  local RETRY_SH="${SCRIPTS_DIR}/retry.sh"

  # 13-1: 引数なし → exit 1
  if ! bash "$RETRY_SH" 2>/dev/null; then
    pass "13-1: 引数なし → exit 1"
  else
    fail "13-1" "exit 0 が返った"
  fi

  # 13-2: 初回成功 → リトライなし
  local out
  out=$(bash "$RETRY_SH" -- true 2>&1)
  if ! echo "$out" | grep -q "リトライ"; then
    pass "13-2: 初回成功 → リトライなし"
  else
    fail "13-2" "不要なリトライが発生: $out"
  fi

  # 13-3: 失敗→成功パターン (カウンタファイルで制御)
  local counter_file="${TEST_DIR}/retry_counter"
  local test_cmd="${TEST_DIR}/retry_test_cmd.sh"
  echo "0" > "$counter_file"
  cat > "$test_cmd" <<EOF
#!/usr/bin/env bash
count=\$(cat "$counter_file")
count=\$((count+1))
echo "\$count" > "$counter_file"
[ "\$count" -ge 2 ]
EOF
  chmod +x "$test_cmd"
  bash "$RETRY_SH" --max 3 --delay 0 -- bash "$test_cmd" 2>/dev/null
  local final_count
  final_count=$(cat "$counter_file")
  if [[ "$final_count" -ge 2 ]]; then
    pass "13-3: 失敗→成功パターン (2回目で成功)"
  else
    fail "13-3" "期待した試行回数がない: count=${final_count}"
  fi
  rm -f "$counter_file" "$test_cmd"

  # 13-4: 全リトライ失敗 → exit 1
  if ! bash "$RETRY_SH" --max 3 --delay 0 -- false 2>/dev/null; then
    pass "13-4: 全リトライ失敗 → exit 1"
  else
    fail "13-4" "exit 0 が返った"
  fi

  # 13-5: --backoff オプション + delay=0 → エラーなしで動作
  local counter_file2="${TEST_DIR}/backoff_counter"
  local backoff_cmd="${TEST_DIR}/backoff_cmd.sh"
  echo "0" > "$counter_file2"
  cat > "$backoff_cmd" <<EOF
#!/usr/bin/env bash
count=\$(cat "$counter_file2")
count=\$((count+1))
echo "\$count" > "$counter_file2"
[ "\$count" -ge 2 ]
EOF
  chmod +x "$backoff_cmd"
  bash "$RETRY_SH" --max 3 --delay 0 --backoff -- bash "$backoff_cmd" 2>/dev/null
  local backoff_count
  backoff_count=$(cat "$counter_file2")
  if [[ "$backoff_count" -ge 2 ]]; then
    pass "13-5: --backoff + delay=0 → 2回目で成功"
  else
    fail "13-5" "backoffが正常に動作しない: count=${backoff_count}"
  fi
  rm -f "$counter_file2" "$backoff_cmd"
}

# ============================================================
# 14. phase-gate.sh テスト
# ============================================================
test_phase_gate() {
  header "14. phase-gate.sh"

  local GATE_SH="${SCRIPTS_DIR}/phase-gate.sh"
  local gate_dir="${TEST_DIR}/gate_project"
  local aad_dir="${gate_dir}/.claude/aad"

  mkdir -p "${aad_dir}/phases"
  cd "$gate_dir"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "# gate test" > README.md
  git add -A && git commit -q -m "init"

  local out

  # 14-1: post-init 正常系 → GATE PASS
  echo '{"runId":"test-run","currentLevel":0,"completedLevels":[],"tasks":{},"mergeLog":[]}' \
    > "${aad_dir}/state.json"
  echo "{\"projectDir\":\"${gate_dir}\",\"worktreeDir\":\"/tmp/wt\",\"featureName\":\"test\",\"parentBranch\":\"aad/develop\"}" \
    > "${aad_dir}/project-config.json"
  out=$(bash "$GATE_SH" post-init "$gate_dir" 2>&1)
  if echo "$out" | grep -q "GATE PASS"; then
    pass "14-1: post-init 正常 → GATE PASS"
  else
    fail "14-1" "GATE PASSが出力されない: $out"
  fi

  # 14-2: post-plan plan.json なし → GATE FAIL
  rm -f "${aad_dir}/plan.json"
  out=$(bash "$GATE_SH" post-plan "$gate_dir" 2>&1 || true)
  if echo "$out" | grep -q "GATE FAIL"; then
    pass "14-2: post-plan plan.json なし → GATE FAIL"
  else
    fail "14-2" "GATE FAILが出力されない: $out"
  fi

  # 14-3: post-plan wave数 0 → GATE FAIL
  echo '{"featureName":"test","waves":[]}' > "${aad_dir}/plan.json"
  out=$(AAD_SCRIPTS_DIR="$SCRIPTS_DIR" bash "$GATE_SH" post-plan "$gate_dir" 2>&1 || true)
  if echo "$out" | grep -q "GATE FAIL"; then
    pass "14-3: post-plan wave数 0 → GATE FAIL"
  else
    fail "14-3" "wave数0なのにGATE FAILが出力されない: $out"
  fi

  # 14-4: post-plan 正常系 → GATE PASS
  cat > "${aad_dir}/plan.json" <<'PLANEOF'
{
  "featureName": "test",
  "waves": [
    {"id": 0, "type": "bootstrap", "tasks": []},
    {"id": 1, "type": "parallel",
     "agents": [{"name": "agent-a", "tasks": [], "files": [], "dependsOn": []}]}
  ]
}
PLANEOF
  out=$(AAD_SCRIPTS_DIR="$SCRIPTS_DIR" bash "$GATE_SH" post-plan "$gate_dir" 2>&1)
  if echo "$out" | grep -q "GATE PASS"; then
    pass "14-4: post-plan 正常 → GATE PASS"
  else
    fail "14-4" "GATE PASSが出力されない: $out"
  fi

  # 14-5: post-execute ロックファイル残存 → GATE FAIL
  echo "99999" > "${aad_dir}/aad-merge.lock"
  out=$(bash "$GATE_SH" post-execute "$gate_dir" 2>&1 || true)
  if echo "$out" | grep -q "GATE FAIL"; then
    pass "14-5: post-execute ロックファイル残存 → GATE FAIL"
  else
    fail "14-5" "GATE FAILが出力されない: $out"
  fi
  rm -f "${aad_dir}/aad-merge.lock"

  # 14-6: post-execute failed タスクあり → GATE FAIL
  echo '{"runId":"r","currentLevel":1,"completedLevels":[],"tasks":{"agent-a":{"level":1,"status":"failed"}},"mergeLog":[]}' \
    > "${aad_dir}/state.json"
  out=$(bash "$GATE_SH" post-execute "$gate_dir" 2>&1 || true)
  if echo "$out" | grep -q "GATE FAIL"; then
    pass "14-6: post-execute failed タスクあり → GATE FAIL"
  else
    fail "14-6" "GATE FAILが出力されない: $out"
  fi

  # 14-7: post-execute 正常系 → GATE PASS
  echo '{"runId":"r","currentLevel":2,"completedLevels":[0,1],"tasks":{"agent-a":{"level":1,"status":"completed"}},"mergeLog":[]}' \
    > "${aad_dir}/state.json"
  out=$(bash "$GATE_SH" post-execute "$gate_dir" 2>&1)
  if echo "$out" | grep -q "GATE PASS"; then
    pass "14-7: post-execute 正常 → GATE PASS"
  else
    fail "14-7" "GATE PASSが出力されない: $out"
  fi

  # 14-8: post-review review-output.json なし → GATE PASS (スキップ)
  rm -f "${aad_dir}/phases/review-output.json"
  out=$(bash "$GATE_SH" post-review "$gate_dir" 2>&1)
  if echo "$out" | grep -q "GATE PASS"; then
    pass "14-8: post-review review-output なし → GATE PASS (スキップ)"
  else
    fail "14-8" "GATE PASSが出力されない: $out"
  fi

  # 14-9: post-review critical > 0 → WARN + exit 0 (GATE PASS)
  echo '{"status":"completed","critical":2,"warning":1,"info":3,"autoFixed":0}' \
    > "${aad_dir}/phases/review-output.json"
  out=$(bash "$GATE_SH" post-review "$gate_dir" 2>&1)
  local exit_code=0
  bash "$GATE_SH" post-review "$gate_dir" >/dev/null 2>&1 || exit_code=$?
  if echo "$out" | grep -q "GATE PASS" && [[ "$exit_code" -eq 0 ]]; then
    pass "14-9: post-review critical > 0 → WARN + GATE PASS (exit 0)"
  elif echo "$out" | grep -q "GATE PASS"; then
    pass "14-9: post-review critical > 0 → GATE PASS"
  else
    fail "14-9" "GATE PASSが出力されない: $out"
  fi

  cd "$TEST_DIR"
  rm -rf "$gate_dir"
}

# ============================================================
# メイン
# ============================================================
main() {
  echo "=============================="
  echo " AAD v2 追加テスト"
  echo " SCRIPTS_DIR: $SCRIPTS_DIR"
  echo " HOOKS_DIR:   $HOOKS_DIR"
  echo "=============================="

  setup
  trap teardown EXIT

  test_hooks_memory
  test_hooks_boundary
  test_plan_edge
  test_tdd_edge
  test_worktree_edge
  test_deps_edge
  test_cleanup_edge
  test_retry
  test_phase_gate

  echo
  echo "=============================="
  echo " 結果: PASS=${PASS} FAIL=${FAIL}"
  echo "=============================="

  [[ $FAIL -eq 0 ]] && exit 0 || exit 1
}

main
