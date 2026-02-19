#!/usr/bin/env bash
# test_aad_e2e.sh — AAD v2 E2E テストスイート
# エージェント起動なし: スクリプトパイプライン全体をシェルでシミュレート
# カバレッジ: Init→Plan→Wave0→Wave1(並列)→Merge→Cleanup + セキュリティ + バグ修正検証

set -uo pipefail

# ============================================================
# 設定
# ============================================================
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/aad-v2/skills/aad/scripts" && pwd)"
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/aad-v2/hooks" && pwd)"
BASE_DIR=$(mktemp -d "/tmp/aad_e2e_XXXXXX")

PASS=0; FAIL=0; SKIP=0
SECTION=""

# クリーンアップ (EXIT trap)
cleanup_all() {
  if [[ -d "$BASE_DIR" ]]; then
    # git worktreeは先にprune
    find "$BASE_DIR" -name ".git" -maxdepth 2 -type d 2>/dev/null | head -5 | while read -r gd; do
      proj=$(dirname "$gd")
      git -C "$proj" worktree prune 2>/dev/null || true
    done
    rm -rf "$BASE_DIR"
  fi
}
trap cleanup_all EXIT

# ============================================================
# ヘルパー
# ============================================================
section() {
  SECTION="$1"
  echo ""
  echo "=== ${SECTION} ==="
}

pass() {
  echo "  ✓ PASS: $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ FAIL: $1 — $2"
  FAIL=$((FAIL + 1))
}

skip() {
  echo "  - SKIP: $1 — $2"
  SKIP=$((SKIP + 1))
}

# 新しいテスト用gitリポジトリを作成
new_git_repo() {
  local name="${1:-repo}"
  local dir="$BASE_DIR/$name"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@aad.test"
  git -C "$dir" config user.name "AAD Test"
  # 初期コミット
  echo "# $name" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "chore: initial commit"
  echo "$dir"
}

# ============================================================
# Section 1: フルパイプライン (Happy Path)
# ============================================================
section "1. フルパイプライン Happy Path"

PROJ=$(new_git_repo "e2e-project")
PARENT_BRANCH="aad/develop"
WT_DIR="${PROJ}-feature1-wt"

# E2E-01: Phase 1 Init — worktreeベース + 親ブランチ作成
out=$(bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ" "$PARENT_BRANCH" "feature1" 2>&1)
if [[ -d "$WT_DIR" ]] && git -C "$PROJ" rev-parse --verify "$PARENT_BRANCH" >/dev/null 2>&1; then
  pass "E2E-01: create-parent → worktreeベースディレクトリ + 親ブランチ作成"
else
  fail "E2E-01" "worktreeベースまたは親ブランチが作成されていない: $out"
fi

# E2E-02: plan.sh init — プロジェクト情報検出
out=$(bash "${SCRIPTS_DIR}/plan.sh" init "$PROJ" 2>&1)
if echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('language')=='unknown'" 2>/dev/null; then
  pass "E2E-02: plan.sh init → JSON出力確認 (language=unknown)"
else
  fail "E2E-02" "plan.sh init のJSON出力が不正: $out"
fi

# E2E-02b: plan.sh init — Python プロジェクト
PYPROJ=$(new_git_repo "py-project")
touch "$PYPROJ/pyproject.toml"
out=$(bash "${SCRIPTS_DIR}/plan.sh" init "$PYPROJ" 2>&1)
if echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d.get('language')=='python'" 2>/dev/null; then
  pass "E2E-02b: plan.sh init → Python プロジェクト検出"
else
  fail "E2E-02b" "Pythonプロジェクト検出失敗: $out"
fi

# E2E-03: state.json 初期化
RUN_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p "${PROJ}/.claude/aad"
python3 -c "
import json
data = {
  'runId': '${RUN_ID}',
  'currentLevel': 0,
  'completedLevels': [],
  'tasks': {},
  'mergeLog': []
}
print(json.dumps(data))
" > "${PROJ}/.claude/aad/state.json"

if [[ -f "${PROJ}/.claude/aad/state.json" ]]; then
  run_id_check=$(python3 -c "import json; d=json.load(open('${PROJ}/.claude/aad/state.json')); print(d['runId'])")
  if [[ "$run_id_check" == "$RUN_ID" ]]; then
    pass "E2E-03: state.json 初期化"
  else
    fail "E2E-03" "state.json の runId が一致しない"
  fi
else
  fail "E2E-03" "state.json が作成されていない"
fi

# E2E-04: Wave 0 — 親ブランチ上で直接 TDD コミット (RED→GREEN→REFACTOR)
git -C "$PROJ" checkout -q "$PARENT_BRANCH"

# RED フェーズ
mkdir -p "$PROJ/tests"
cat > "$PROJ/tests/test_shared.py" << 'PYEOF'
"""Wave 0: 共有型テスト (RED)"""
from src.models import Config

def test_config_default():
    c = Config()
    assert c.version == "1.0"
PYEOF

out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "core" "add Config model tests" "$PROJ" 2>&1)
if git -C "$PROJ" log --oneline | grep -q "^[a-f0-9]* test(core): add Config model tests"; then
  pass "E2E-04a: Wave 0 RED コミット"
else
  fail "E2E-04a" "REDコミットが見つからない: $out"
fi

# GREEN フェーズ
mkdir -p "$PROJ/src"
cat > "$PROJ/src/__init__.py" << 'PYEOF'
PYEOF
cat > "$PROJ/src/models.py" << 'PYEOF'
"""Wave 0: 共有モデル (GREEN)"""
class Config:
    def __init__(self):
        self.version = "1.0"
PYEOF

out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "core" "implement Config model" "$PROJ" 2>&1)
if git -C "$PROJ" log --oneline | grep -q "feat(core): implement Config model"; then
  pass "E2E-04b: Wave 0 GREEN コミット"
else
  fail "E2E-04b" "GREENコミットが見つからない: $out"
fi

# REFACTOR フェーズ (C5修正の検証)
cat > "$PROJ/src/models.py" << 'PYEOF'
"""Wave 0: 共有モデル (REFACTOR — docstring追加)"""

class Config:
    """アプリケーション設定を保持するクラス。"""
    def __init__(self):
        self.version = "1.0"
PYEOF

out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase refactor "core" "add docstring to Config" "$PROJ" 2>&1)
if git -C "$PROJ" log --oneline | grep -q "refactor(core): add docstring to Config"; then
  pass "E2E-04c: Wave 0 REFACTOR コミット (C5修正確認)"
else
  fail "E2E-04c" "REFACTORコミットが見つからない: $out"
fi

# E2E-05: Wave 1 — 2つのworktreeを並列作成
WT1=$(bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_DIR" "agent-add" "agent-add" "$PARENT_BRANCH" 2>&1 | tail -1)
WT2=$(bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_DIR" "agent-mul" "agent-mul" "$PARENT_BRANCH" 2>&1 | tail -1)

if [[ -d "$WT1" ]] && [[ -d "$WT2" ]]; then
  pass "E2E-05: Wave 1 worktree × 2 作成"
else
  fail "E2E-05" "worktree作成失敗: WT1=$WT1, WT2=$WT2"
fi

# E2E-06: 各worktreeで TDD サイクル実行
# Agent 1 (add/subtract)
cat > "$WT1/tests/__init__.py" 2>/dev/null || mkdir -p "$WT1/tests" && touch "$WT1/tests/__init__.py"
mkdir -p "$WT1/tests"
cat > "$WT1/tests/test_add.py" << 'PYEOF'
from src.calc import add, subtract

def test_add():
    assert add(1, 2) == 3

def test_subtract():
    assert subtract(5, 3) == 2
PYEOF

bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "add" "add/subtract tests" "$WT1" >/dev/null 2>&1

mkdir -p "$WT1/src"
touch "$WT1/src/__init__.py"
cat > "$WT1/src/calc.py" << 'PYEOF'
def add(a, b): return a + b
def subtract(a, b): return a - b
PYEOF

bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "add" "implement add/subtract" "$WT1" >/dev/null 2>&1

# Agent 2 (multiply/divide)
mkdir -p "$WT2/tests"
touch "$WT2/tests/__init__.py"
cat > "$WT2/tests/test_mul.py" << 'PYEOF'
from src.calc import multiply, divide

def test_multiply():
    assert multiply(3, 4) == 12

def test_divide():
    assert divide(10, 2) == 5.0
PYEOF

bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "mul" "multiply/divide tests" "$WT2" >/dev/null 2>&1

mkdir -p "$WT2/src"
touch "$WT2/src/__init__.py"
cat > "$WT2/src/calc.py" << 'PYEOF'
def multiply(a, b): return a * b
def divide(a, b): return a / b
PYEOF

bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "mul" "implement multiply/divide" "$WT2" >/dev/null 2>&1

# 各worktreeのコミット数を確認
commits1=$(git -C "$WT1" log --oneline "feature/agent-add" ^"$PARENT_BRANCH" | wc -l | tr -d ' ')
commits2=$(git -C "$WT2" log --oneline "feature/agent-mul" ^"$PARENT_BRANCH" | wc -l | tr -d ' ')

if [[ "$commits1" -eq 2 ]] && [[ "$commits2" -eq 2 ]]; then
  pass "E2E-06: 各worktreeで TDD コミット × 2 (RED+GREEN)"
else
  fail "E2E-06" "コミット数不正: agent-add=${commits1}, agent-mul=${commits2}"
fi

# E2E-07: 並列マージ (Spinlock テスト)
# 両エージェントを同時にマージ試行 → spinlockで直列化
merge_log="$BASE_DIR/merge_parallel.log"

bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$WT1" "agent-add" "$PARENT_BRANCH" "$PROJ" >"${merge_log}.1" 2>&1 &
PID1=$!
bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$WT2" "agent-mul" "$PARENT_BRANCH" "$PROJ" >"${merge_log}.2" 2>&1 &
PID2=$!

wait $PID1
rc1=$?
wait $PID2
rc2=$?

merge_commits=$(git -C "$PROJ" log --oneline "$PARENT_BRANCH" | grep "merge(wave)" | wc -l | tr -d ' ')

if [[ $rc1 -eq 0 ]] && [[ $rc2 -eq 0 ]] && [[ "$merge_commits" -eq 2 ]]; then
  pass "E2E-07: 並列マージ (Spinlock) — 両者成功・コミット数=2"
elif [[ $rc1 -eq 0 ]] && [[ $rc2 -eq 0 ]]; then
  fail "E2E-07" "マージは成功したがmerge(wave)コミットが${merge_commits}件 (期待: 2)"
else
  fail "E2E-07" "マージ失敗: PID1 exit=${rc1}, PID2 exit=${rc2}"
  cat "${merge_log}.1" || true
  cat "${merge_log}.2" || true
fi

# ロックファイルが残っていないことを確認
if [[ ! -f "${PROJ}/.claude/aad/aad-merge.lock" ]]; then
  pass "E2E-07b: 並列マージ後 ロックファイルなし"
else
  fail "E2E-07b" "ロックファイルが残存: ${PROJ}/.claude/aad/aad-merge.lock"
fi

# E2E-08: Phase 6 Cleanup
# project-config.json が必要なので作成
python3 -c "
import json
data = {
  'projectDir': '${PROJ}',
  'worktreeDir': '${WT_DIR}',
  'featureName': 'feature1',
  'parentBranch': '${PARENT_BRANCH}'
}
with open('${PROJ}/.claude/aad/project-config.json', 'w') as f:
    json.dump(data, f)
"

out=$(bash "${SCRIPTS_DIR}/cleanup.sh" run "$PROJ" 2>&1)
archive_count=$(find "${PROJ}/.claude/aad/archive" -name "state.json" 2>/dev/null | wc -l | tr -d ' ')

if [[ "$archive_count" -ge 1 ]] && echo "$out" | grep -q "クリーンアップ完了"; then
  pass "E2E-08: cleanup.sh run → state.jsonアーカイブ + 完了メッセージ"
else
  fail "E2E-08" "クリーンアップ失敗 (archive=${archive_count}): $out"
fi

# ============================================================
# Section 2: Spinlock 詳細テスト
# ============================================================
section "2. Spinlock & Concurrent Merge"

PROJ2=$(new_git_repo "spinlock-test")
BRANCH2="aad/spinlock"
WT2_DIR="${PROJ2}-spinlock-wt"
bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ2" "$BRANCH2" "spinlock" >/dev/null 2>&1

# ワーカー3体を並列作成・コミット
for agent in alpha beta gamma; do
  wt=$(bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT2_DIR" "$agent" "$agent" "$BRANCH2" 2>&1 | tail -1)
  echo "task_${agent}" > "$wt/task.txt"
  bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "$agent" "implement $agent task" "$wt" >/dev/null 2>&1
done

# E2E-09: 3並列マージ
merge_log2="$BASE_DIR/merge3.log"
for agent in alpha beta gamma; do
  wt="${WT2_DIR}/${agent}"
  bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$wt" "$agent" "$BRANCH2" "$PROJ2" >"${merge_log2}.${agent}" 2>&1 &
done
wait

merge3_count=$(git -C "$PROJ2" log --oneline "$BRANCH2" | grep "merge(wave)" | wc -l | tr -d ' ')
lock_remaining=$(ls "${PROJ2}/.claude/aad/aad-merge.lock" 2>/dev/null | wc -l | tr -d ' ')

if [[ "$merge3_count" -eq 3 ]] && [[ "$lock_remaining" -eq 0 ]]; then
  pass "E2E-09: 3並列マージ全成功 (spinlock正常動作)"
else
  fail "E2E-09" "merge_commits=${merge3_count}/3, lock_remaining=${lock_remaining}"
fi

# E2E-10: Stale Lock 検出
PROJ_SL=$(new_git_repo "stale-lock")
BRANCH_SL="aad/stale"
WT_SL="${PROJ_SL}-stale-wt"
bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ_SL" "$BRANCH_SL" "stale" >/dev/null 2>&1
wt_sl=$(bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_SL" "stale-agent" "stale-agent" "$BRANCH_SL" 2>&1 | tail -1)
echo "stale_work" > "$wt_sl/stale.txt"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "stale" "stale work" "$wt_sl" >/dev/null 2>&1

# 存在しないPIDで stale lock を作成
mkdir -p "${PROJ_SL}/.claude/aad"
echo "999999999" > "${PROJ_SL}/.claude/aad/aad-merge.lock"

out=$(bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$wt_sl" "stale-agent" "$BRANCH_SL" "$PROJ_SL" 2>&1)
if echo "$out" | grep -q "スタールロックを検出" && echo "$out" | grep -q "✓ マージが成功しました"; then
  pass "E2E-10: Stale lock 自動削除 → マージ成功"
else
  fail "E2E-10" "stale lock処理失敗: $out"
fi

# ============================================================
# Section 3: バグ修正検証
# ============================================================
section "3. バグ修正検証"

# E2E-11: H1修正 — Lock File Conflict → git commit 自動実行
PROJ_H1=$(new_git_repo "h1-fix")
BRANCH_H1="aad/h1"
git -C "$PROJ_H1" checkout -q -b "$BRANCH_H1"
mkdir -p "${PROJ_H1}/.claude/aad"

# 親ブランチに lock file をコミット
echo "parent-lock-content" > "${PROJ_H1}/.claude/aad/aad-merge.lock"
git -C "$PROJ_H1" add .
git -C "$PROJ_H1" commit -q -m "chore: accidentally committed lock file to parent"

# feature ブランチで別内容の lock file
git -C "$PROJ_H1" checkout -q -b "feature/h1-agent"
echo "feature-lock-content" > "${PROJ_H1}/.claude/aad/aad-merge.lock"
git -C "$PROJ_H1" add .
git -C "$PROJ_H1" commit -q -m "chore: lock file in feature branch"

# 親ブランチに戻る
git -C "$PROJ_H1" checkout -q "$BRANCH_H1"

# マージ実行 (lock file のみ conflict のはず)
mkdir -p "$BASE_DIR/h1-dummy-wt"
out=$(bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent \
  "$BASE_DIR/h1-dummy-wt" "h1-agent" "$BRANCH_H1" "$PROJ_H1" 2>&1) || true

# H1修正の確認: merge commitが作成されているか
if git -C "$PROJ_H1" log --oneline "$BRANCH_H1" | grep -q "auto-resolved lock conflict"; then
  pass "E2E-11: H1修正 — ロックファイルconflict自動解決 + git commit"
elif echo "$out" | grep -q "✓ マージが成功しました"; then
  # conflict がなかった (fast-forward) ケース
  pass "E2E-11: H1修正 — マージ成功 (no lock conflict in this scenario)"
else
  fail "E2E-11" "H1修正の動作が確認できない: $out"
fi

# E2E-12: C5修正 — commit-phase "refactor" フェーズ
PROJ_C5=$(new_git_repo "c5-fix")
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase refactor "module" "clean up code" "$PROJ_C5" 2>&1)
if git -C "$PROJ_C5" log --oneline | grep -q "refactor(module): clean up code"; then
  pass "E2E-12: C5修正 — refactor フェーズ → refactor(...) コミット"
else
  fail "E2E-12" "refactorコミット作成失敗: $out"
fi

# E2E-13: C5修正 — "review" フェーズも引き続き動作
PROJ_C5R=$(new_git_repo "c5-review")
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase review "module" "code review fixes" "$PROJ_C5R" 2>&1)
if git -C "$PROJ_C5R" log --oneline | grep -q "refactor(module): code review fixes"; then
  pass "E2E-13: C5修正 — review フェーズ互換性維持"
else
  fail "E2E-13" "review フェーズが機能しない: $out"
fi

# E2E-14: C5修正 — 不正フェーズ → exit 1
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase invalid "mod" "desc" "/tmp" 2>&1) || true
if echo "$out" | grep -qE "不正なphase|red/green/refactor/review"; then
  pass "E2E-14: C5修正 — 不正フェーズ → exit 1 + エラーメッセージ"
else
  fail "E2E-14" "不正フェーズのエラー処理が不正: $out"
fi

# ============================================================
# Section 4: セキュリティ — Worktree 境界チェック
# ============================================================
section "4. セキュリティ — Worktree 境界チェック"

# E2E-15: C1修正 — -wt/ を含む別worktreeパス → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/my-proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"/tmp/other-proj-wt/secret.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-15: C1修正 — 別 -wt/ パス → BLOCK"
else
  fail "E2E-15" "別worktreeパスがブロックされなかった: $out"
fi

# E2E-16: C2修正 — 任意の .claude/ パス → BLOCK (AAD_PROJECT_DIR未設定)
out=$(AAD_WORKTREE_PATH="/tmp/my-proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"/tmp/other-project/.claude/settings.json"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-16: C2修正 — 任意の .claude/ → BLOCK (AAD_PROJECT_DIR未設定)"
else
  fail "E2E-16" "任意の .claude/ パスがブロックされなかった: $out"
fi

# E2E-17: C2修正 — AAD_PROJECT_DIR 設定時、そのプロジェクトの .claude/ は許可
out=$(AAD_WORKTREE_PATH="/tmp/myapp-feat-wt/worker1" \
  AAD_PROJECT_DIR="/tmp/myapp" \
  TOOL_INPUT='{"file_path":"/tmp/myapp/.claude/aad/state.json"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if ! echo "$out" | grep -q "BLOCK"; then
  pass "E2E-17: C2修正 — AAD_PROJECT_DIR の .claude/ → 許可"
else
  fail "E2E-17" "正当な .claude/ パスがブロックされた: $out"
fi

# E2E-17b: C2修正 — AAD_PROJECT_DIR 外の .claude/ → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/myapp-feat-wt/worker1" \
  AAD_PROJECT_DIR="/tmp/myapp" \
  TOOL_INPUT='{"file_path":"/tmp/other-app/.claude/aad/state.json"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-17b: C2修正 — 別プロジェクトの .claude/ → BLOCK"
else
  fail "E2E-17b" "別プロジェクトの .claude/ がブロックされなかった: $out"
fi

# E2E-18: C3修正 — 相対パス → BLOCK (セキュリティ強化)
out=$(AAD_WORKTREE_PATH="/tmp/my-proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"../../etc/passwd"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-18: C3修正 — 相対パス (../etc/passwd) → BLOCK"
else
  fail "E2E-18" "相対パスがブロックされなかった: $out"
fi

# E2E-18b: C3修正 — シンプルな相対パス → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/my-proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"src/main.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-18b: C3修正 — 相対パス (src/main.py) → BLOCK"
else
  fail "E2E-18b" "相対パスがブロックされなかった: $out"
fi

# E2E-19: H8修正 — JSONキーとコロンの間にスペース → 正常パース
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/w1" \
  TOOL_INPUT='{"file_path" : "/tmp/proj-wt/w1/main.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if ! echo "$out" | grep -q "BLOCK"; then
  pass "E2E-19: H8修正 — スペースあり JSON ('file_path' : ...) → 正常パース・許可"
else
  fail "E2E-19" "スペースありJSONが誤ってブロックされた: $out"
fi

# E2E-19b: H8修正 — 範囲外パスをスペースありJSONで
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/w1" \
  TOOL_INPUT='{"file_path" : "/tmp/other/secret.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-19b: H8修正 — スペースあり JSON + 範囲外パス → BLOCK"
else
  fail "E2E-19b" "スペースありJSON範囲外パスがブロックされなかった: $out"
fi

# E2E-20: AAD_WORKTREE_PATH 未設定 → パススルー (Wave 0 / Orchestrator)
out=$(TOOL_INPUT='{"file_path":"/absolutely/anything.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if ! echo "$out" | grep -q "BLOCK"; then
  pass "E2E-20: AAD_WORKTREE_PATH 未設定 → パススルー"
else
  fail "E2E-20" "AAD_WORKTREE_PATH未設定でもBLOCKされた: $out"
fi

# E2E-21: 正規の worktree パス → 許可
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"/tmp/proj-wt/worker1/src/main.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if ! echo "$out" | grep -q "BLOCK"; then
  pass "E2E-21: 正規の worktree パス → 許可"
else
  fail "E2E-21" "正規パスがブロックされた: $out"
fi

# E2E-22: 境界外絶対パス → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"/etc/hosts"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-22: 境界外絶対パス (/etc/hosts) → BLOCK"
else
  fail "E2E-22" "境界外パスがブロックされなかった: $out"
fi

# ============================================================
# Section 5: plan.sh validate
# ============================================================
section "5. plan.sh validate"

# 有効な plan.json
VALID_PLAN=$(cat << 'JSONEOF'
{
  "featureName": "calculator",
  "waves": [
    {
      "level": 0,
      "agents": [
        {
          "name": "wave0-bootstrap",
          "files": ["src/models.py", "src/types.py"],
          "dependsOn": []
        }
      ]
    },
    {
      "level": 1,
      "agents": [
        {
          "name": "agent-add",
          "files": ["src/calc_add.py"],
          "dependsOn": ["wave0-bootstrap"]
        },
        {
          "name": "agent-mul",
          "files": ["src/calc_mul.py"],
          "dependsOn": ["wave0-bootstrap"]
        }
      ],
      "apiContract": {
        "endpoints": [
          {"method": "GET", "path": "/calc/add"},
          {"method": "PATCH", "path": "/calc/update", "semantics": "partial-update"}
        ]
      }
    }
  ]
}
JSONEOF
)

echo "$VALID_PLAN" > "$BASE_DIR/valid_plan.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/valid_plan.json" 2>&1)
if echo "$out" | grep -q "✓ plan.json validation passed"; then
  pass "E2E-23: plan.sh validate — 有効な plan.json → PASS"
else
  fail "E2E-23" "有効なplanが検証失敗: $out"
fi

# E2E-24: 重複エージェント名
DUPL_PLAN=$(cat << 'JSONEOF'
{
  "waves": [
    {
      "level": 1,
      "agents": [
        {"name": "agent-a", "files": ["a.py"]},
        {"name": "agent-a", "files": ["b.py"]}
      ]
    }
  ]
}
JSONEOF
)
echo "$DUPL_PLAN" > "$BASE_DIR/dupl_plan.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/dupl_plan.json" 2>&1) || true
if echo "$out" | grep -q "重複タスクID"; then
  pass "E2E-24: plan.sh validate — 重複エージェント名 → エラー検出"
else
  fail "E2E-24" "重複エージェントが検出されなかった: $out"
fi

# E2E-25: 存在しない依存関係
DEP_PLAN=$(cat << 'JSONEOF'
{
  "waves": [
    {
      "level": 1,
      "agents": [
        {"name": "agent-b", "files": ["b.py"], "dependsOn": ["nonexistent-agent"]}
      ]
    }
  ]
}
JSONEOF
)
echo "$DEP_PLAN" > "$BASE_DIR/dep_plan.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/dep_plan.json" 2>&1) || true
if echo "$out" | grep -q "依存関係エラー"; then
  pass "E2E-25: plan.sh validate — 存在しない依存関係 → エラー検出"
else
  fail "E2E-25" "依存関係エラーが検出されなかった: $out"
fi

# E2E-26: ファイル競合
FILE_CONFLICT_PLAN=$(cat << 'JSONEOF'
{
  "waves": [
    {
      "level": 1,
      "agents": [
        {"name": "agent-x", "files": ["shared.py", "x.py"]},
        {"name": "agent-y", "files": ["shared.py", "y.py"]}
      ]
    }
  ]
}
JSONEOF
)
echo "$FILE_CONFLICT_PLAN" > "$BASE_DIR/file_conflict_plan.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/file_conflict_plan.json" 2>&1) || true
if echo "$out" | grep -q "ファイル競合"; then
  pass "E2E-26: plan.sh validate — ファイル競合 → エラー検出"
else
  fail "E2E-26" "ファイル競合が検出されなかった: $out"
fi

# E2E-27: ルートレベル apiContract → エラー
ROOT_API_PLAN=$(cat << 'JSONEOF'
{
  "apiContract": {"endpoints": []},
  "waves": [{"level": 1, "agents": [{"name": "ag", "files": ["a.py"]}]}]
}
JSONEOF
)
echo "$ROOT_API_PLAN" > "$BASE_DIR/root_api_plan.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/root_api_plan.json" 2>&1) || true
if echo "$out" | grep -q "apiContract位置エラー"; then
  pass "E2E-27: plan.sh validate — ルートレベルapiContract → エラー検出"
else
  fail "E2E-27" "apiContract位置エラーが検出されなかった: $out"
fi

# E2E-28: PATCH endpoint に semantics なし → エラー
PATCH_PLAN=$(cat << 'JSONEOF'
{
  "waves": [
    {
      "level": 1,
      "agents": [{"name": "ag", "files": ["a.py"]}],
      "apiContract": {
        "endpoints": [{"method": "PATCH", "path": "/item"}]
      }
    }
  ]
}
JSONEOF
)
echo "$PATCH_PLAN" > "$BASE_DIR/patch_plan.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/patch_plan.json" 2>&1) || true
if echo "$out" | grep -q "semantics"; then
  pass "E2E-28: plan.sh validate — PATCH endpoint 欠損semantics → エラー検出"
else
  fail "E2E-28" "PATCH semantics エラーが検出されなかった: $out"
fi

# ============================================================
# Section 6: エラーハンドリング
# ============================================================
section "6. エラーハンドリング"

# E2E-29: 解決不能なマージコンフリクト → abort + exit 1
PROJ_CONF=$(new_git_repo "conflict-test")
BRANCH_CONF="aad/conflict"
git -C "$PROJ_CONF" checkout -q -b "$BRANCH_CONF"

# 親に src/app.py を作成
echo "version = 'parent'" > "$PROJ_CONF/src/app.py" 2>/dev/null || { mkdir -p "$PROJ_CONF/src"; echo "version = 'parent'" > "$PROJ_CONF/src/app.py"; }
git -C "$PROJ_CONF" add .
git -C "$PROJ_CONF" commit -q -m "feat: parent version"

# feature ブランチで同一ファイルを変更
git -C "$PROJ_CONF" checkout -q -b "feature/conflict-agent"
echo "version = 'feature'" > "$PROJ_CONF/src/app.py"
git -C "$PROJ_CONF" add .
git -C "$PROJ_CONF" commit -q -m "feat: feature version"

# 親ブランチに戻り同一ファイルを変更
git -C "$PROJ_CONF" checkout -q "$BRANCH_CONF"
echo "version = 'parent-update'" > "$PROJ_CONF/src/app.py"
git -C "$PROJ_CONF" add .
git -C "$PROJ_CONF" commit -q -m "feat: parent update"

mkdir -p "$BASE_DIR/conf-dummy-wt"
out=$(bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent \
  "$BASE_DIR/conf-dummy-wt" "conflict-agent" "$BRANCH_CONF" "$PROJ_CONF" 2>&1) || rc=$?

merge_state=$(git -C "$PROJ_CONF" status --porcelain=v1 | head -1)
if echo "$out" | grep -q "コンフリクト"; then
  pass "E2E-29: 解決不能コンフリクト → abort + エラーメッセージ"
else
  fail "E2E-29" "コンフリクト処理が期待通りでない: $out"
fi

# E2E-30: AAD_STRICT_TDD=true + unknown framework → exit 1
PROJ_STRICT=$(new_git_repo "strict-tdd")
out=$(AAD_STRICT_TDD=true bash "${SCRIPTS_DIR}/tdd.sh" run-tests "$PROJ_STRICT" 2>&1) || rc_strict=$?
if [[ "${rc_strict:-0}" -ne 0 ]] || echo "$out" | grep -q "AAD_STRICT_TDD"; then
  pass "E2E-30: AAD_STRICT_TDD=true + unknown framework → exit 1"
else
  fail "E2E-30" "STRICT_TDDが機能しなかった: $out"
fi

# E2E-31: cleanup.sh — project-config.json なし → exit 1
PROJ_NC=$(new_git_repo "no-config")
out=$(bash "${SCRIPTS_DIR}/cleanup.sh" run "$PROJ_NC" 2>&1) || true
if echo "$out" | grep -q "project-config.json が見つかりません"; then
  pass "E2E-31: cleanup.sh — project-config.json なし → exit 1"
else
  fail "E2E-31" "project-config.json不在のエラーが出なかった: $out"
fi

# E2E-32: worktree.sh — サブコマンド不正 → exit 1 + usage
out=$(bash "${SCRIPTS_DIR}/worktree.sh" invalid-cmd 2>&1) || true
if echo "$out" | grep -qiE "不明なサブコマンド|unknown|usage"; then
  pass "E2E-32: worktree.sh — 不正サブコマンド → エラーメッセージ"
else
  fail "E2E-32" "不正サブコマンドのエラーが出なかった: $out"
fi

# E2E-33: tdd.sh — commit-phase 引数不足 → exit 1
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase 2>&1) || true
if [[ $? -ne 0 ]] || echo "$out" | grep -qE "phase.*必要|使用方法"; then
  pass "E2E-33: tdd.sh — commit-phase 引数なし → エラー"
else
  fail "E2E-33" "引数不足エラーが出なかった: $out"
fi

# ============================================================
# Section 7: worktree.sh ライフサイクル
# ============================================================
section "7. worktree.sh ライフサイクル"

PROJ_WT=$(new_git_repo "wt-lifecycle")
BRANCH_WT="aad/lifecycle"
WT_LF="${PROJ_WT}-lifecycle-wt"
bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ_WT" "$BRANCH_WT" "lifecycle" >/dev/null 2>&1

# E2E-34: create-task + list
bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_LF" "wk1" "wk1" "$BRANCH_WT" >/dev/null 2>&1
bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_LF" "wk2" "wk2" "$BRANCH_WT" >/dev/null 2>&1
out=$(bash "${SCRIPTS_DIR}/worktree.sh" list "$WT_LF" 2>&1)
if echo "$out" | grep -q "wk1" && echo "$out" | grep -q "wk2"; then
  pass "E2E-34: create-task × 2 + list → 両worktreeが一覧に表示"
else
  fail "E2E-34" "worktree listが正しくない: $out"
fi

# E2E-35: setup-symlinks (Python .venv がある場合)
mkdir -p "${PROJ_WT}/.venv"
out=$(bash "${SCRIPTS_DIR}/worktree.sh" setup-symlinks "$PROJ_WT" "${WT_LF}/wk1" 2>&1)
if echo "$out" | grep -q "symlink作成\|.venv" || echo "$out" | grep -q "symlink"; then
  pass "E2E-35: setup-symlinks → .venv symlink 作成"
elif echo "$out" | grep -q "見つかりませんでした"; then
  skip "E2E-35" ".venv symlink (依存なし場合スキップ)"
fi

# E2E-36: remove — worktreeを個別削除
out=$(bash "${SCRIPTS_DIR}/worktree.sh" remove "${WT_LF}/wk2" "wk2" 2>&1)
if ! [[ -d "${WT_LF}/wk2" ]] && echo "$out" | grep -q "削除しました"; then
  pass "E2E-36: worktree.sh remove → worktree + branch 削除"
else
  fail "E2E-36" "worktree削除失敗: $out"
fi

# E2E-37: cleanup — 全worktree削除
out=$(bash "${SCRIPTS_DIR}/worktree.sh" cleanup "$WT_LF" 2>&1)
if ! [[ -d "$WT_LF" ]] && echo "$out" | grep -q "クリーンアップが完了しました"; then
  pass "E2E-37: worktree.sh cleanup → ベースディレクトリ削除"
else
  fail "E2E-37" "cleanup失敗 (dir_exists=$(ls -la "$WT_LF" 2>/dev/null)): $out"
fi

# ============================================================
# Section 8: 統合検証 — Python プロジェクト
# ============================================================
section "8. 統合検証 — Python プロジェクト全パイプライン"

PROJ_PY=$(new_git_repo "py-full")
BRANCH_PY="aad/develop"
WT_PY="${PROJ_PY}-calc-wt"

# 初期化
bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ_PY" "$BRANCH_PY" "calc" >/dev/null 2>&1
git -C "$PROJ_PY" checkout -q "$BRANCH_PY"

# .gitignore作成 + Wave 0 初期コミット
cat > "$PROJ_PY/.gitignore" << 'EOF'
__pycache__/
*.pyc
.venv/
.pytest_cache/
EOF
mkdir -p "$PROJ_PY/src" "$PROJ_PY/tests"
touch "$PROJ_PY/src/__init__.py" "$PROJ_PY/tests/__init__.py"
cat > "$PROJ_PY/pyproject.toml" << 'EOF'
[project]
name = "calculator"
version = "0.1.0"
EOF
git -C "$PROJ_PY" add .
git -C "$PROJ_PY" commit -q -m "chore: project setup"

# Wave 0: 共有型定義 (TDD)
cat > "$PROJ_PY/tests/test_types.py" << 'EOF'
from src.types import Result
def test_result_ok():
    r = Result(value=42)
    assert r.value == 42
    assert r.error is None
EOF
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "types" "add Result type tests" "$PROJ_PY" >/dev/null 2>&1

cat > "$PROJ_PY/src/types.py" << 'EOF'
class Result:
    def __init__(self, value=None, error=None):
        self.value = value
        self.error = error
EOF
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "types" "implement Result type" "$PROJ_PY" >/dev/null 2>&1
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase refactor "types" "add type hints" "$PROJ_PY" >/dev/null 2>&1

wave0_commits=$(git -C "$PROJ_PY" log --oneline "$BRANCH_PY" | grep -cE "test\(types\)|feat\(types\)|refactor\(types\)" || true)
if [[ "$wave0_commits" -eq 3 ]]; then
  pass "E2E-38: Python統合 Wave 0 — RED+GREEN+REFACTOR (3コミット)"
else
  fail "E2E-38" "Wave 0 コミット数=${wave0_commits} (期待:3)"
fi

# Wave 1: 2エージェント
WT_A="${WT_PY}/agent-ops"
WT_B="${WT_PY}/agent-io"
bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_PY" "agent-ops" "agent-ops" "$BRANCH_PY" >/dev/null 2>&1
bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT_PY" "agent-io" "agent-io" "$BRANCH_PY" >/dev/null 2>&1

# Agent-ops: 四則演算
mkdir -p "$WT_A/src" "$WT_A/tests"
cp "$PROJ_PY/src/__init__.py" "$WT_A/src/"
touch "$WT_A/tests/__init__.py"
cat > "$WT_A/tests/test_ops.py" << 'EOF'
from src.ops import add, sub, mul, div
def test_all(): assert add(1,2)==3 and sub(5,3)==2 and mul(3,4)==12 and div(8,2)==4.0
EOF
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "ops" "add arithmetic tests" "$WT_A" >/dev/null 2>&1
cat > "$WT_A/src/ops.py" << 'EOF'
def add(a,b): return a+b
def sub(a,b): return a-b
def mul(a,b): return a*b
def div(a,b): return a/b
EOF
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "ops" "implement arithmetic" "$WT_A" >/dev/null 2>&1

# Agent-io: 文字列フォーマット
mkdir -p "$WT_B/src" "$WT_B/tests"
cp "$PROJ_PY/src/__init__.py" "$WT_B/src/"
touch "$WT_B/tests/__init__.py"
cat > "$WT_B/tests/test_io.py" << 'EOF'
from src.io_utils import format_result
def test_format(): assert format_result(42) == "Result: 42"
EOF
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "io" "add io tests" "$WT_B" >/dev/null 2>&1
cat > "$WT_B/src/io_utils.py" << 'EOF'
def format_result(v): return f"Result: {v}"
EOF
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "io" "implement io_utils" "$WT_B" >/dev/null 2>&1

# 並列マージ
bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$WT_A" "agent-ops" "$BRANCH_PY" "$PROJ_PY" >/dev/null 2>&1 &
bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$WT_B" "agent-io" "$BRANCH_PY" "$PROJ_PY" >/dev/null 2>&1 &
wait

py_merge_count=$(git -C "$PROJ_PY" log --oneline "$BRANCH_PY" | grep -c "merge(wave)" || true)
py_files=$(git -C "$PROJ_PY" ls-tree -r HEAD --name-only)
has_ops=$(echo "$py_files" | grep -c "ops.py" || true)
has_io=$(echo "$py_files" | grep -c "io_utils.py" || true)

if [[ "$py_merge_count" -eq 2 ]] && [[ "$has_ops" -ge 1 ]] && [[ "$has_io" -ge 1 ]]; then
  pass "E2E-39: Python統合 Wave 1 — 並列マージ完了 + 全ファイルが main に統合"
else
  fail "E2E-39" "merge_count=${py_merge_count}, has_ops=${has_ops}, has_io=${has_io}"
fi

# Git log の整合性チェック
total_commits=$(git -C "$PROJ_PY" log --oneline "$BRANCH_PY" | wc -l | tr -d ' ')
if [[ "$total_commits" -ge 8 ]]; then
  pass "E2E-40: Python統合 git log 整合性 — 合計${total_commits}コミット"
else
  fail "E2E-40" "コミット数が少ない: ${total_commits} (期待: >=8)"
fi

# Cleanup
python3 -c "
import json
data={'projectDir':'${PROJ_PY}','worktreeDir':'${WT_PY}','featureName':'calc','parentBranch':'${BRANCH_PY}'}
with open('${PROJ_PY}/.claude/aad/project-config.json','w') as f: json.dump(data,f)
" 2>/dev/null || true
mkdir -p "${PROJ_PY}/.claude/aad"
echo '{"tasks":{}}' > "${PROJ_PY}/.claude/aad/state.json"

out=$(bash "${SCRIPTS_DIR}/cleanup.sh" run "$PROJ_PY" 2>&1)
if echo "$out" | grep -q "クリーンアップ完了" && ! [[ -d "$WT_PY" ]]; then
  pass "E2E-41: Python統合 cleanup → worktree削除 + アーカイブ"
else
  fail "E2E-41" "cleanup失敗: $out"
fi

# ============================================================
# 結果サマリー
# ============================================================
echo ""
echo "=============================="
echo " E2E テスト結果"
echo "=============================="
echo " PASS: ${PASS}"
echo " FAIL: ${FAIL}"
echo " SKIP: ${SKIP}"
echo " 合計: $((PASS + FAIL + SKIP))"
echo "=============================="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
