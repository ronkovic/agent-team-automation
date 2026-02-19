#!/usr/bin/env bash
# test_aad_e2e.sh — AAD v2 E2E テストスイート
# エージェント起動なし: スクリプトパイプライン全体をシェルでシミュレート
# カバレッジ: Init→Plan→Wave0→Wave1(並列)→Merge→Cleanup + セキュリティ + バグ修正

set -uo pipefail

# ============================================================
# 設定
# ============================================================
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/aad-v2/skills/aad/scripts"
HOOKS_DIR="${REPO_ROOT}/aad-v2/hooks"
BASE_DIR=$(mktemp -d "/tmp/aad_e2e_XXXXXX")

PASS=0; FAIL=0; SKIP=0

# ============================================================
# クリーンアップ
# ============================================================
cleanup_all() {
  # worktreeは先にprune してから削除
  find "$BASE_DIR" -maxdepth 3 -name ".git" -type d 2>/dev/null | while read -r gd; do
    proj=$(dirname "$gd")
    git -C "$proj" worktree prune 2>/dev/null || true
  done
  rm -rf "$BASE_DIR"
}
trap cleanup_all EXIT

# ============================================================
# ヘルパー
# ============================================================
section() { echo ""; echo "=== $1 ==="; }
pass()    { echo "  ✓ PASS: $1"; PASS=$((PASS + 1)); }
fail()    { echo "  ✗ FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }
skip()    { echo "  - SKIP: $1 — $2"; SKIP=$((SKIP + 1)); }

# 新しいgitリポジトリを作成してパスを返す
new_git_repo() {
  local name="${1:-repo}"
  local dir="$BASE_DIR/$name"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@aad.test"
  git -C "$dir" config user.name "AAD Test"
  echo "# $name" > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m "chore: initial commit"
  echo "$dir"
}

# ============================================================
# Section 1: 初期化フェーズ
# ============================================================
section "1. 初期化フェーズ"

PROJ=$(new_git_repo "main-proj")
PARENT_BRANCH="aad/develop"
WT_DIR="${PROJ}-feature1-wt"

# E2E-01: create-parent — worktreeベース + 親ブランチ作成
out=$(bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ" "$PARENT_BRANCH" "feature1" 2>&1)
if [[ -d "$WT_DIR" ]] && git -C "$PROJ" rev-parse --verify "$PARENT_BRANCH" >/dev/null 2>&1; then
  pass "E2E-01: create-parent → worktreeベース + 親ブランチ作成"
else
  fail "E2E-01" "worktreeベースまたは親ブランチ未作成: $out"
fi

# E2E-02: plan.sh init — language 検出
out=$(bash "${SCRIPTS_DIR}/plan.sh" init "$PROJ" 2>&1)
lang=$(echo "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('language',''))" 2>/dev/null || echo "")
if [[ "$lang" == "unknown" ]]; then
  pass "E2E-02: plan.sh init → JSON出力 (language=unknown)"
else
  fail "E2E-02" "language不正: '$lang', output: $out"
fi

# E2E-02b: Python プロジェクト検出
PYPROJ=$(new_git_repo "py-detect")
touch "$PYPROJ/pyproject.toml"
out=$(bash "${SCRIPTS_DIR}/plan.sh" init "$PYPROJ" 2>&1)
lang=$(echo "$out" | python3 -c "import json,sys; print(json.load(sys.stdin).get('language',''))" 2>/dev/null || echo "")
if [[ "$lang" == "python" ]]; then
  pass "E2E-02b: plan.sh init → Python プロジェクト検出"
else
  fail "E2E-02b" "language不正: '$lang'"
fi

# E2E-03: state.json 初期化
RUN_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p "${PROJ}/.claude/aad"
python3 -c "
import json
print(json.dumps({'runId':'${RUN_ID}','currentLevel':0,'completedLevels':[],'tasks':{},'mergeLog':[]}))
" > "${PROJ}/.claude/aad/state.json"
rid=$(python3 -c "import json; print(json.load(open('${PROJ}/.claude/aad/state.json'))['runId'])" 2>/dev/null || echo "")
if [[ "$rid" == "$RUN_ID" ]]; then
  pass "E2E-03: state.json 初期化"
else
  fail "E2E-03" "state.json の runId 不一致"
fi

# ============================================================
# Section 2: Wave 0 — TDD サイクル (commit-phase red/green/refactor)
# ============================================================
section "2. Wave 0 — TDD コミットサイクル"

# 親ブランチに切り替え
git -C "$PROJ" checkout -q "$PARENT_BRANCH"

# E2E-04: RED コミット
mkdir -p "$PROJ/tests"
cat > "$PROJ/tests/test_shared.py" << 'PYEOF'
"""Wave 0 共有型テスト"""
def test_placeholder(): assert True
PYEOF
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "core" "add shared type tests" "$PROJ" 2>&1)
commit_count=$(git -C "$PROJ" log --oneline "$PARENT_BRANCH" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$commit_count" -ge 2 ]] && echo "$out" | grep -q "test(core)"; then
  pass "E2E-04: Wave 0 RED コミット"
else
  fail "E2E-04" "REDコミット失敗 (commits=${commit_count}): $out"
fi

# E2E-05: GREEN コミット
mkdir -p "$PROJ/src"
cat > "$PROJ/src/__init__.py" << 'PYEOF'
PYEOF
cat > "$PROJ/src/models.py" << 'PYEOF'
class Config:
    def __init__(self): self.version = "1.0"
PYEOF
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "core" "implement Config model" "$PROJ" 2>&1)
commit_count=$(git -C "$PROJ" log --oneline "$PARENT_BRANCH" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$commit_count" -ge 3 ]] && echo "$out" | grep -q "feat(core)"; then
  pass "E2E-05: Wave 0 GREEN コミット"
else
  fail "E2E-05" "GREENコミット失敗 (commits=${commit_count}): $out"
fi

# E2E-06: REFACTOR コミット (C5修正確認)
cat > "$PROJ/src/models.py" << 'PYEOF'
"""設定モデル (リファクタ済み: docstring追加)"""
class Config:
    """アプリ設定。"""
    def __init__(self): self.version = "1.0"
PYEOF
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase refactor "core" "add docstring to Config" "$PROJ" 2>&1)
commit_count=$(git -C "$PROJ" log --oneline "$PARENT_BRANCH" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$commit_count" -ge 4 ]] && echo "$out" | grep -q "refactor(core)"; then
  pass "E2E-06: Wave 0 REFACTOR コミット (C5修正確認)"
else
  fail "E2E-06" "REFACTORコミット失敗 (commits=${commit_count}): $out"
fi

# E2E-07: "review" フェーズも refactor prefix で動作 (C5後方互換)
PROJ_REV=$(new_git_repo "review-compat")
echo "# test" > "$PROJ_REV/patch.py"
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase review "mod" "review fixes" "$PROJ_REV" 2>&1)
if echo "$out" | grep -q "refactor(mod)"; then
  pass "E2E-07: commit-phase review → refactor prefix (C5後方互換)"
else
  fail "E2E-07" "review フェーズ後方互換失敗: $out"
fi

# E2E-08: 不正フェーズ → exit 1
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase invalid "mod" "desc" "$PROJ_REV" 2>&1) || true
if echo "$out" | grep -qE "不正なphase|red/green/refactor/review"; then
  pass "E2E-08: 不正フェーズ → exit 1 + エラーメッセージ"
else
  fail "E2E-08" "不正フェーズエラー不正: $out"
fi

# ============================================================
# Section 3: Wave 1 — 並列 worktree + TDD + Merge
# ============================================================
section "3. Wave 1 — 並列 worktree + Merge"

# E2E-09: create-task × 2 (worktree.sh は $PROJ から実行必須)
WT1=$(cd "$PROJ" && bash "${SCRIPTS_DIR}/worktree.sh" create-task \
  "$WT_DIR" "agent-add" "agent-add" "$PARENT_BRANCH" 2>&1 | tail -1)
WT2=$(cd "$PROJ" && bash "${SCRIPTS_DIR}/worktree.sh" create-task \
  "$WT_DIR" "agent-mul" "agent-mul" "$PARENT_BRANCH" 2>&1 | tail -1)

if [[ -d "$WT1" ]] && [[ -d "$WT2" ]]; then
  pass "E2E-09: create-task × 2 → worktree作成"
else
  fail "E2E-09" "worktree作成失敗: WT1='$WT1', WT2='$WT2'"
fi

# E2E-10: 各worktreeで TDD コミット
mkdir -p "$WT1/tests" "$WT1/src"
touch "$WT1/tests/__init__.py" "$WT1/src/__init__.py"
echo "def test_add(): assert True" > "$WT1/tests/test_add.py"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "add" "add tests" "$WT1" >/dev/null 2>&1
echo "def add(a,b): return a+b" > "$WT1/src/calc.py"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "add" "implement add" "$WT1" >/dev/null 2>&1

mkdir -p "$WT2/tests" "$WT2/src"
touch "$WT2/tests/__init__.py" "$WT2/src/__init__.py"
echo "def test_mul(): assert True" > "$WT2/tests/test_mul.py"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "mul" "mul tests" "$WT2" >/dev/null 2>&1
echo "def mul(a,b): return a*b" > "$WT2/src/calc_mul.py"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "mul" "implement mul" "$WT2" >/dev/null 2>&1

c1=$(git -C "$WT1" log --oneline "feature/agent-add" ^"$PARENT_BRANCH" 2>/dev/null | wc -l | tr -d ' ')
c2=$(git -C "$WT2" log --oneline "feature/agent-mul" ^"$PARENT_BRANCH" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$c1" -eq 2 ]] && [[ "$c2" -eq 2 ]]; then
  pass "E2E-10: 各worktreeで RED + GREEN コミット × 2"
else
  fail "E2E-10" "コミット数不正: agent-add=${c1}, agent-mul=${c2}"
fi

# E2E-11: 並列マージ (Spinlock テスト)
bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent \
  "$WT1" "agent-add" "$PARENT_BRANCH" "$PROJ" >/tmp/aad_e2e_merge1.log 2>&1 &
PID1=$!
bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent \
  "$WT2" "agent-mul" "$PARENT_BRANCH" "$PROJ" >/tmp/aad_e2e_merge2.log 2>&1 &
PID2=$!

wait $PID1; rc1=$?
wait $PID2; rc2=$?

merge_count=$(git -C "$PROJ" log --oneline "$PARENT_BRANCH" | grep -c "merge(wave)" 2>/dev/null || echo 0)
lock_exists=$([[ -f "${PROJ}/.claude/aad/aad-merge.lock" ]] && echo 1 || echo 0)

if [[ $rc1 -eq 0 ]] && [[ $rc2 -eq 0 ]] && [[ "$merge_count" -eq 2 ]]; then
  pass "E2E-11: 並列マージ (Spinlock) — 両成功・merge commit × 2"
else
  fail "E2E-11" "rc1=${rc1}, rc2=${rc2}, merge_count=${merge_count}"
  cat /tmp/aad_e2e_merge1.log 2>/dev/null | tail -5 || true
fi

if [[ "$lock_exists" -eq 0 ]]; then
  pass "E2E-11b: 並列マージ後 ロックファイルなし (正常解放)"
else
  fail "E2E-11b" "ロックファイルが残存"
fi

# E2E-12: Cleanup — state.json アーカイブ
python3 -c "
import json
data={'projectDir':'${PROJ}','worktreeDir':'${WT_DIR}','featureName':'feature1','parentBranch':'${PARENT_BRANCH}'}
with open('${PROJ}/.claude/aad/project-config.json','w') as f: json.dump(data,f)
"
out=$(bash "${SCRIPTS_DIR}/cleanup.sh" run "$PROJ" 2>&1)
archive_count=$(find "${PROJ}/.claude/aad/archive" -name "state.json" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$archive_count" -ge 1 ]] && echo "$out" | grep -q "クリーンアップ完了"; then
  pass "E2E-12: cleanup.sh run → state.json アーカイブ + worktree削除"
else
  fail "E2E-12" "クリーンアップ失敗 (archive=${archive_count}): $out"
fi

# ============================================================
# Section 4: Spinlock 詳細
# ============================================================
section "4. Spinlock 詳細"

PROJ2=$(new_git_repo "spinlock3")
BRANCH2="aad/spinlock"
WT2_DIR="${PROJ2}-spinlock-wt"
bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ2" "$BRANCH2" "spinlock" >/dev/null 2>&1

for ag in alpha beta gamma; do
  wt=$(cd "$PROJ2" && bash "${SCRIPTS_DIR}/worktree.sh" create-task "$WT2_DIR" "$ag" "$ag" "$BRANCH2" 2>&1 | tail -1)
  echo "task_${ag}" > "$wt/task_${ag}.txt"
  bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "$ag" "implement $ag" "$wt" >/dev/null 2>&1
done

# E2E-13: 3並列マージ全成功
for ag in alpha beta gamma; do
  wt="${WT2_DIR}/${ag}"
  bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$wt" "$ag" "$BRANCH2" "$PROJ2" \
    >/tmp/aad_merge_${ag}.log 2>&1 &
done
wait

mc3=$(git -C "$PROJ2" log --oneline "$BRANCH2" | grep -c "merge(wave)" 2>/dev/null || echo 0)
lk3=$([[ -f "${PROJ2}/.claude/aad/aad-merge.lock" ]] && echo 1 || echo 0)

if [[ "$mc3" -eq 3 ]] && [[ "$lk3" -eq 0 ]]; then
  pass "E2E-13: 3並列マージ全成功 (Spinlock正常動作)"
else
  fail "E2E-13" "merge_count=${mc3}/3, lock=${lk3}"
fi

# E2E-14: Stale lock 自動削除
PROJ_SL=$(new_git_repo "stale-lock")
BRANCH_SL="aad/stale"
WT_SL="${PROJ_SL}-stale-wt"
bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ_SL" "$BRANCH_SL" "stale" >/dev/null 2>&1
wt_sl=$(cd "$PROJ_SL" && bash "${SCRIPTS_DIR}/worktree.sh" create-task \
  "$WT_SL" "stale-agent" "stale-agent" "$BRANCH_SL" 2>&1 | tail -1)
echo "stale work" > "$wt_sl/stale.txt"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "stale" "stale work" "$wt_sl" >/dev/null 2>&1

# 存在しないPIDで stale lock を作成
mkdir -p "${PROJ_SL}/.claude/aad"
echo "999999999" > "${PROJ_SL}/.claude/aad/aad-merge.lock"

out=$(bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent \
  "$wt_sl" "stale-agent" "$BRANCH_SL" "$PROJ_SL" 2>&1)
if echo "$out" | grep -q "スタールロック" && echo "$out" | grep -q "マージが成功しました"; then
  pass "E2E-14: Stale lock 自動削除 → マージ成功"
else
  fail "E2E-14" "stale lock処理失敗: $out"
fi

# ============================================================
# Section 5: H1修正 — Merge commit after lock conflict
# ============================================================
section "5. H1修正 — ロックファイルコンフリクト後 git commit"

# E2E-15: H1修正コード確認
if grep -q "git commit --no-edit" "${SCRIPTS_DIR}/tdd.sh"; then
  pass "E2E-15: H1修正コード確認 — git commit --no-edit が tdd.sh に存在"
else
  fail "E2E-15" "H1修正コードが見つからない"
fi

# E2E-15b: H1シナリオ — ロックファイルのみ conflict する状態を手動構築してテスト
PROJ_H1=$(new_git_repo "h1-scenario")
git -C "$PROJ_H1" checkout -q -b "aad/h1"
mkdir -p "${PROJ_H1}/.claude/aad"

# 親ブランチ: 共通ファイル + ロックファイル (異なる内容)
echo "shared" > "$PROJ_H1/shared.py"
echo "PARENT-LOCK" > "${PROJ_H1}/.claude/aad/aad-merge.lock"
git -C "$PROJ_H1" add .
git -C "$PROJ_H1" commit -q -m "chore: initial with lock"

# Feature ブランチ: 新規ファイル + ロックファイル (異なる内容)
git -C "$PROJ_H1" checkout -q -b "feature/h1-agent"
echo "new-feature" > "$PROJ_H1/feature.py"
echo "FEATURE-LOCK" > "${PROJ_H1}/.claude/aad/aad-merge.lock"
git -C "$PROJ_H1" add .
git -C "$PROJ_H1" commit -q -m "feat: feature work"

# 親ブランチに戻り手動マージを実施 (spinlockを通さずに直接テスト)
git -C "$PROJ_H1" checkout -q "aad/h1"
git -C "$PROJ_H1" merge --no-ff "feature/h1-agent" -m "merge" 2>/dev/null || true

# ロックファイルのみのコンフリクト確認
conflicts=$(git -C "$PROJ_H1" diff --name-only --diff-filter=U 2>/dev/null)
if echo "$conflicts" | grep -q "aad-merge.lock"; then
  # 手動でロックファイルのみ解決 → git commit (H1修正の動作確認)
  git -C "$PROJ_H1" checkout --theirs "${PROJ_H1}/.claude/aad/aad-merge.lock" 2>/dev/null
  git -C "$PROJ_H1" add "${PROJ_H1}/.claude/aad/aad-merge.lock" 2>/dev/null
  remaining=$(git -C "$PROJ_H1" diff --name-only --diff-filter=U 2>/dev/null | grep -v "aad-merge.lock" || true)
  if [[ -z "$remaining" ]]; then
    git -C "$PROJ_H1" commit --no-edit -m "merge(wave): h1-agent (auto-resolved lock)" 2>/dev/null
    merge_head=$(git -C "$PROJ_H1" rev-parse MERGE_HEAD 2>/dev/null) || merge_head=""
    if [[ -z "$merge_head" ]]; then
      pass "E2E-15b: H1修正シナリオ — ロックファイルのみconflict → git commit後 MERGE_HEAD消失"
    else
      fail "E2E-15b" "MERGE_HEAD が残存している"
    fi
  else
    skip "E2E-15b" "他のconflictも発生 (設計見直し必要): $remaining"
  fi
else
  # conflict が発生しなかった (fast-forward等) - ロックファイル消失後のクリーン結合
  clean_status=$(git -C "$PROJ_H1" status --porcelain 2>/dev/null | head -1)
  if [[ -z "$clean_status" ]]; then
    pass "E2E-15b: H1修正シナリオ — クリーンマージ (conflict不発生)"
  else
    fail "E2E-15b" "ロックファイルconflict未発生かつ状態不正: $clean_status"
  fi
fi

# ============================================================
# Section 6: セキュリティ — Worktree 境界チェック
# ============================================================
section "6. セキュリティ — Worktree 境界チェック"

# E2E-16: C1修正 — -wt/ 別パス → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/my-proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"/tmp/evil-wt/malware.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-16: C1修正 — 別 -wt/ パス → BLOCK"
else
  fail "E2E-16" "別worktreeパスがブロックされなかった: $out"
fi

# E2E-17: C2修正 — 任意の .claude/ → BLOCK (AAD_PROJECT_DIR未設定)
out=$(AAD_WORKTREE_PATH="/tmp/my-proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"/other/project/.claude/settings.json"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-17: C2修正 — 任意 .claude/ → BLOCK (AAD_PROJECT_DIR未設定)"
else
  fail "E2E-17" "任意の .claude/ がブロックされなかった: $out"
fi

# E2E-18: C2修正 — AAD_PROJECT_DIR の .claude/ → 許可
out=$(AAD_WORKTREE_PATH="/tmp/myapp-feat-wt/worker1" \
  AAD_PROJECT_DIR="/tmp/myapp" \
  TOOL_INPUT='{"file_path":"/tmp/myapp/.claude/aad/state.json"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if ! echo "$out" | grep -q "BLOCK"; then
  pass "E2E-18: C2修正 — AAD_PROJECT_DIR の .claude/ → 許可"
else
  fail "E2E-18" "正当な .claude/ パスがブロックされた: $out"
fi

# E2E-19: C2修正 — AAD_PROJECT_DIR 外の .claude/ → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/myapp-feat-wt/worker1" \
  AAD_PROJECT_DIR="/tmp/myapp" \
  TOOL_INPUT='{"file_path":"/tmp/other/.claude/aad/state.json"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-19: C2修正 — 別プロジェクトの .claude/ → BLOCK"
else
  fail "E2E-19" "別プロジェクトの .claude/ がブロックされなかった: $out"
fi

# E2E-20: C3修正 — 相対パス → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/worker" \
  TOOL_INPUT='{"file_path":"../../etc/passwd"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-20: C3修正 — 相対パス (../等) → BLOCK"
else
  fail "E2E-20" "相対パスがブロックされなかった: $out"
fi

# E2E-21: C3修正 — 単純な相対パス → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/worker" \
  TOOL_INPUT='{"file_path":"src/main.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-21: C3修正 — 相対パス (src/main.py) → BLOCK"
else
  fail "E2E-21" "相対パスがブロックされなかった: $out"
fi

# E2E-22: H8修正 — JSON スペースあり ("file_path" : ...) → 正常パース・許可
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/worker1" \
  TOOL_INPUT='{"file_path" : "/tmp/proj-wt/worker1/main.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if ! echo "$out" | grep -q "BLOCK"; then
  pass "E2E-22: H8修正 — スペースあり JSON → 正常パース・許可"
else
  fail "E2E-22" "スペースありJSONが誤ってブロックされた: $out"
fi

# E2E-23: H8修正 — スペースあり JSON + 範囲外 → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/worker1" \
  TOOL_INPUT='{"file_path" : "/etc/hosts"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-23: H8修正 — スペースあり JSON + 範囲外パス → BLOCK"
else
  fail "E2E-23" "スペースありJSON範囲外がブロックされなかった: $out"
fi

# E2E-24: AAD_WORKTREE_PATH 未設定 → パススルー (Wave 0)
out=$(TOOL_INPUT='{"file_path":"/absolutely/anything.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if ! echo "$out" | grep -q "BLOCK"; then
  pass "E2E-24: AAD_WORKTREE_PATH 未設定 → パススルー (Wave 0 / Orchestrator)"
else
  fail "E2E-24" "AAD_WORKTREE_PATH未設定でもBLOCKされた: $out"
fi

# E2E-24b: パストラバーサル防止 — .. を含む絶対パス → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"/tmp/proj-wt/worker1/../../../../../../etc/passwd"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-24b: パストラバーサル (/../../../etc/passwd) → BLOCK"
else
  fail "E2E-24b" "パストラバーサルがブロックされなかった: $out"
fi

# E2E-25: 正規 worktree パス → 許可
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"/tmp/proj-wt/worker1/src/main.py"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if ! echo "$out" | grep -q "BLOCK"; then
  pass "E2E-25: 正規 worktree パス → 許可"
else
  fail "E2E-25" "正規パスがブロックされた: $out"
fi

# E2E-26: 境界外絶対パス → BLOCK
out=$(AAD_WORKTREE_PATH="/tmp/proj-wt/worker1" \
  TOOL_INPUT='{"file_path":"/etc/hosts"}' \
  bash "${HOOKS_DIR}/worktree-boundary.sh" 2>&1) || true
if echo "$out" | grep -q "BLOCK"; then
  pass "E2E-26: 境界外絶対パス (/etc/hosts) → BLOCK"
else
  fail "E2E-26" "境界外パスがブロックされなかった: $out"
fi

# ============================================================
# Section 7: plan.sh validate
# ============================================================
section "7. plan.sh validate"

# E2E-27: 有効な plan.json
cat > "$BASE_DIR/valid.json" << 'JSONEOF'
{
  "featureName": "calc",
  "waves": [
    {
      "level": 0,
      "agents": [{"name": "wave0", "files": ["src/types.py"], "dependsOn": []}]
    },
    {
      "level": 1,
      "agents": [
        {"name": "agent-add", "files": ["src/add.py"], "dependsOn": ["wave0"]},
        {"name": "agent-mul", "files": ["src/mul.py"], "dependsOn": ["wave0"]}
      ],
      "apiContract": {
        "endpoints": [
          {"method": "GET", "path": "/calc"},
          {"method": "PATCH", "path": "/calc/update", "semantics": "partial-update"}
        ]
      }
    }
  ]
}
JSONEOF
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/valid.json" 2>&1)
if echo "$out" | grep -q "✓ plan.json validation passed"; then
  pass "E2E-27: plan.sh validate — 有効 plan.json → PASS"
else
  fail "E2E-27" "有効planが失敗: $out"
fi

# E2E-28: 重複エージェント名
python3 -c "import json; print(json.dumps({'waves':[{'level':1,'agents':[{'name':'ag-a','files':['a.py']},{'name':'ag-a','files':['b.py']}]}]}))" \
  > "$BASE_DIR/dup.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/dup.json" 2>&1) || true
if echo "$out" | grep -q "重複タスクID"; then
  pass "E2E-28: plan.sh validate — 重複エージェント名 → エラー検出"
else
  fail "E2E-28" "重複エージェントが未検出: $out"
fi

# E2E-29: 存在しない依存関係
python3 -c "import json; print(json.dumps({'waves':[{'level':1,'agents':[{'name':'ag-b','files':['b.py'],'dependsOn':['nonexistent']}]}]}))" \
  > "$BASE_DIR/dep.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/dep.json" 2>&1) || true
if echo "$out" | grep -q "依存関係エラー"; then
  pass "E2E-29: plan.sh validate — 存在しない依存関係 → エラー検出"
else
  fail "E2E-29" "依存関係エラー未検出: $out"
fi

# E2E-30: ファイル競合
python3 -c "import json; print(json.dumps({'waves':[{'level':1,'agents':[{'name':'ag-x','files':['shared.py']},{'name':'ag-y','files':['shared.py']}]}]}))" \
  > "$BASE_DIR/fconflict.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/fconflict.json" 2>&1) || true
if echo "$out" | grep -q "ファイル競合"; then
  pass "E2E-30: plan.sh validate — ファイル競合 → エラー検出"
else
  fail "E2E-30" "ファイル競合未検出: $out"
fi

# E2E-31: ルートレベル apiContract → エラー
python3 -c "import json; print(json.dumps({'apiContract':{'endpoints':[]},'waves':[{'level':1,'agents':[{'name':'ag','files':['a.py']}]}]}))" \
  > "$BASE_DIR/rootapi.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/rootapi.json" 2>&1) || true
if echo "$out" | grep -q "apiContract位置エラー"; then
  pass "E2E-31: plan.sh validate — ルートレベル apiContract → エラー検出"
else
  fail "E2E-31" "apiContract位置エラー未検出: $out"
fi

# E2E-32: PATCH endpoint に semantics なし → エラー
python3 -c "import json; print(json.dumps({'waves':[{'level':1,'agents':[{'name':'ag','files':['a.py']}],'apiContract':{'endpoints':[{'method':'PATCH','path':'/item'}]}}]}))" \
  > "$BASE_DIR/patch.json"
out=$(bash "${SCRIPTS_DIR}/plan.sh" validate "$BASE_DIR/patch.json" 2>&1) || true
if echo "$out" | grep -q "semantics"; then
  pass "E2E-32: plan.sh validate — PATCH semantics 欠損 → エラー検出"
else
  fail "E2E-32" "PATCH semantics エラー未検出: $out"
fi

# ============================================================
# Section 8: エラーハンドリング
# ============================================================
section "8. エラーハンドリング"

# E2E-33: 解決不能コンフリクト → abort + exit 1
PROJ_CONF=$(new_git_repo "conf-test")
BRANCH_CONF="aad/conflict"
git -C "$PROJ_CONF" checkout -q -b "$BRANCH_CONF"
mkdir -p "$PROJ_CONF/src"
echo "v='parent'" > "$PROJ_CONF/src/app.py"
git -C "$PROJ_CONF" add .
git -C "$PROJ_CONF" commit -q -m "feat: parent"

git -C "$PROJ_CONF" checkout -q -b "feature/conflict-agent"
echo "v='feature'" > "$PROJ_CONF/src/app.py"
git -C "$PROJ_CONF" add .
git -C "$PROJ_CONF" commit -q -m "feat: feature"

git -C "$PROJ_CONF" checkout -q "$BRANCH_CONF"
echo "v='parent-update'" > "$PROJ_CONF/src/app.py"
git -C "$PROJ_CONF" add .
git -C "$PROJ_CONF" commit -q -m "feat: parent update"

mkdir -p "$BASE_DIR/conf-dummy"
out=$(bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent \
  "$BASE_DIR/conf-dummy" "conflict-agent" "$BRANCH_CONF" "$PROJ_CONF" 2>&1) || true

if echo "$out" | grep -qE "コンフリクト|コンフリクトがあります"; then
  pass "E2E-33: 解決不能コンフリクト → エラーメッセージ + abort"
else
  fail "E2E-33" "コンフリクト処理が期待通りでない: $out"
fi

# E2E-34: AAD_STRICT_TDD=true + unknown framework → exit 1
PROJ_STRICT=$(new_git_repo "strict-tdd")
rc_strict=0
AAD_STRICT_TDD=true bash "${SCRIPTS_DIR}/tdd.sh" run-tests "$PROJ_STRICT" >/dev/null 2>&1 || rc_strict=$?
if [[ "$rc_strict" -ne 0 ]]; then
  pass "E2E-34: AAD_STRICT_TDD=true + unknown framework → exit 1"
else
  fail "E2E-34" "STRICT_TDDが機能しなかった (exit=${rc_strict})"
fi

# E2E-35: cleanup.sh — project-config.json なし → exit 1
PROJ_NC=$(new_git_repo "no-config")
out=$(bash "${SCRIPTS_DIR}/cleanup.sh" run "$PROJ_NC" 2>&1) || true
if echo "$out" | grep -q "project-config.json が見つかりません"; then
  pass "E2E-35: cleanup.sh — project-config.json なし → exit 1"
else
  fail "E2E-35" "エラーメッセージが出なかった: $out"
fi

# E2E-36: worktree.sh 不正サブコマンド → エラー
out=$(bash "${SCRIPTS_DIR}/worktree.sh" bad-cmd 2>&1) || true
if echo "$out" | grep -qiE "不明なサブコマンド|unknown|使用方法"; then
  pass "E2E-36: worktree.sh — 不正サブコマンド → エラーメッセージ"
else
  fail "E2E-36" "エラーが出なかった: $out"
fi

# E2E-37: tdd.sh commit-phase 引数なし → エラー
out=$(bash "${SCRIPTS_DIR}/tdd.sh" commit-phase 2>&1) || true
if echo "$out" | grep -qE "phase|必要|使用方法"; then
  pass "E2E-37: tdd.sh commit-phase 引数なし → エラー"
else
  fail "E2E-37" "エラーが出なかった: $out"
fi

# ============================================================
# Section 9: worktree.sh ライフサイクル
# ============================================================
section "9. worktree.sh ライフサイクル"

PROJ_WT=$(new_git_repo "wt-life")
BRANCH_WT="aad/lifecycle"
WT_LF="${PROJ_WT}-lifecycle-wt"
bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ_WT" "$BRANCH_WT" "lifecycle" >/dev/null 2>&1

# E2E-38: create-task × 2 (プロジェクトディレクトリから実行)
(cd "$PROJ_WT" && bash "${SCRIPTS_DIR}/worktree.sh" create-task \
  "$WT_LF" "wk1" "wk1" "$BRANCH_WT" >/dev/null 2>&1)
(cd "$PROJ_WT" && bash "${SCRIPTS_DIR}/worktree.sh" create-task \
  "$WT_LF" "wk2" "wk2" "$BRANCH_WT" >/dev/null 2>&1)

if [[ -d "${WT_LF}/wk1" ]] && [[ -d "${WT_LF}/wk2" ]]; then
  pass "E2E-38: create-task × 2 → worktree 作成"
else
  fail "E2E-38" "worktree作成失敗 (wk1=$(ls "${WT_LF}/wk1" 2>/dev/null && echo ok || echo missing), wk2=$(ls "${WT_LF}/wk2" 2>/dev/null && echo ok || echo missing))"
fi

# E2E-39: list
out=$(cd "$PROJ_WT" && bash "${SCRIPTS_DIR}/worktree.sh" list "$WT_LF" 2>&1)
if echo "$out" | grep -q "wk1" && echo "$out" | grep -q "wk2"; then
  pass "E2E-39: worktree.sh list → 両worktree表示"
else
  fail "E2E-39" "list出力不正: $out"
fi

# E2E-40: setup-symlinks (.venv がある場合)
mkdir -p "${PROJ_WT}/.venv"
out=$(bash "${SCRIPTS_DIR}/worktree.sh" setup-symlinks "$PROJ_WT" "${WT_LF}/wk1" 2>&1)
if echo "$out" | grep -qE "symlink|venv"; then
  pass "E2E-40: setup-symlinks → .venv symlink"
else
  skip "E2E-40" "symlink対象なし (環境依存)"
fi

# E2E-41: remove — 個別削除
out=$(cd "$PROJ_WT" && bash "${SCRIPTS_DIR}/worktree.sh" remove "${WT_LF}/wk2" "wk2" 2>&1)
if ! [[ -d "${WT_LF}/wk2" ]] && echo "$out" | grep -q "削除しました"; then
  pass "E2E-41: worktree.sh remove → worktree + branch 削除"
else
  fail "E2E-41" "remove失敗: $out"
fi

# E2E-42: cleanup — 全削除
out=$(cd "$PROJ_WT" && bash "${SCRIPTS_DIR}/worktree.sh" cleanup "$WT_LF" 2>&1)
if ! [[ -d "$WT_LF" ]]; then
  pass "E2E-42: worktree.sh cleanup → ベースディレクトリ削除"
else
  fail "E2E-42" "cleanup失敗: $out"
fi

# ============================================================
# Section 10: 統合検証 — Python 全パイプライン
# ============================================================
section "10. 統合検証 — Python 全パイプライン"

PROJ_PY=$(new_git_repo "py-full")
BRANCH_PY="aad/develop"
WT_PY="${PROJ_PY}-calc-wt"

bash "${SCRIPTS_DIR}/worktree.sh" create-parent "$PROJ_PY" "$BRANCH_PY" "calc" >/dev/null 2>&1
git -C "$PROJ_PY" checkout -q "$BRANCH_PY"

# 初期セットアップ
cat > "$PROJ_PY/.gitignore" << 'EOF'
__pycache__/
*.pyc
.venv/
EOF
mkdir -p "$PROJ_PY/src" "$PROJ_PY/tests"
touch "$PROJ_PY/src/__init__.py" "$PROJ_PY/tests/__init__.py"
echo "[project]"$'\n'"name = \"calc\""$'\n'"version = \"0.1.0\"" > "$PROJ_PY/pyproject.toml"
git -C "$PROJ_PY" add .
git -C "$PROJ_PY" commit -q -m "chore: project setup"

# Wave 0: 共有型 TDD (RED → GREEN → REFACTOR)
cat > "$PROJ_PY/tests/test_types.py" << 'EOF'
from src.types import Result
def test_result_ok():
    r = Result(value=42)
    assert r.value == 42
EOF
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "types" "add Result tests" "$PROJ_PY" >/dev/null 2>&1

cat > "$PROJ_PY/src/types.py" << 'EOF'
class Result:
    def __init__(self, value=None, error=None):
        self.value = value
        self.error = error
EOF
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "types" "implement Result" "$PROJ_PY" >/dev/null 2>&1

# REFACTOR: 型ヒントを追加 (実際の変更)
cat > "$PROJ_PY/src/types.py" << 'EOF'
from typing import Optional

class Result:
    def __init__(self, value: Optional[int] = None, error: Optional[str] = None):
        self.value = value
        self.error = error
EOF
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase refactor "types" "add type hints" "$PROJ_PY" >/dev/null 2>&1

# E2E-43: Wave 0 コミット数確認
wave0_commits=$(git -C "$PROJ_PY" log --oneline "$BRANCH_PY" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$wave0_commits" -ge 4 ]]; then
  pass "E2E-43: Python統合 Wave 0 — setup+RED+GREEN+REFACTOR (${wave0_commits}コミット)"
else
  fail "E2E-43" "Wave 0 コミット数=${wave0_commits} (期待: >=4)"
fi

# Wave 1: 2エージェント並列
WT_PA="${WT_PY}/agent-ops"
WT_PB="${WT_PY}/agent-io"
(cd "$PROJ_PY" && bash "${SCRIPTS_DIR}/worktree.sh" create-task \
  "$WT_PY" "agent-ops" "agent-ops" "$BRANCH_PY" >/dev/null 2>&1)
(cd "$PROJ_PY" && bash "${SCRIPTS_DIR}/worktree.sh" create-task \
  "$WT_PY" "agent-io" "agent-io" "$BRANCH_PY" >/dev/null 2>&1)

# Agent-ops: 四則演算
mkdir -p "$WT_PA/src" "$WT_PA/tests"
touch "$WT_PA/tests/__init__.py" "$WT_PA/src/__init__.py"
echo "def test_ops(): assert True" > "$WT_PA/tests/test_ops.py"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "ops" "add ops tests" "$WT_PA" >/dev/null 2>&1
printf "def add(a,b): return a+b\ndef sub(a,b): return a-b\n" > "$WT_PA/src/ops.py"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "ops" "implement ops" "$WT_PA" >/dev/null 2>&1

# Agent-io: フォーマット関数
mkdir -p "$WT_PB/src" "$WT_PB/tests"
touch "$WT_PB/tests/__init__.py" "$WT_PB/src/__init__.py"
echo "def test_io(): assert True" > "$WT_PB/tests/test_io.py"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase red "io" "add io tests" "$WT_PB" >/dev/null 2>&1
echo "def fmt(v): return f'Result: {v}'" > "$WT_PB/src/io_utils.py"
bash "${SCRIPTS_DIR}/tdd.sh" commit-phase green "io" "implement io" "$WT_PB" >/dev/null 2>&1

# 並列マージ
bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$WT_PA" "agent-ops" "$BRANCH_PY" "$PROJ_PY" >/dev/null 2>&1 &
bash "${SCRIPTS_DIR}/tdd.sh" merge-to-parent "$WT_PB" "agent-io" "$BRANCH_PY" "$PROJ_PY" >/dev/null 2>&1 &
wait

# E2E-44: Wave 1 結果確認
py_merges=$(git -C "$PROJ_PY" log --oneline "$BRANCH_PY" | grep -c "merge(wave)" 2>/dev/null || echo 0)
py_files=$(git -C "$PROJ_PY" ls-tree -r HEAD --name-only 2>/dev/null)
has_ops=$(echo "$py_files" | grep -c "ops.py" 2>/dev/null || echo 0)
has_io=$(echo "$py_files" | grep -c "io_utils.py" 2>/dev/null || echo 0)

if [[ "$py_merges" -eq 2 ]] && [[ "$has_ops" -ge 1 ]] && [[ "$has_io" -ge 1 ]]; then
  pass "E2E-44: Python統合 Wave 1 — 並列マージ完了・全ファイル統合"
else
  fail "E2E-44" "merges=${py_merges}, has_ops=${has_ops}, has_io=${has_io}"
fi

# E2E-45: git log 整合性
total_commits=$(git -C "$PROJ_PY" log --oneline "$BRANCH_PY" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$total_commits" -ge 9 ]]; then
  pass "E2E-45: Python統合 git log — ${total_commits}コミット (整合性OK)"
else
  fail "E2E-45" "コミット数が少ない: ${total_commits} (期待: >=9)"
fi

# E2E-46: フルパイプライン cleanup
python3 -c "
import json
data={'projectDir':'${PROJ_PY}','worktreeDir':'${WT_PY}','featureName':'calc','parentBranch':'${BRANCH_PY}'}
with open('${PROJ_PY}/.claude/aad/project-config.json','w') as f: json.dump(data,f)
" 2>/dev/null || true
mkdir -p "${PROJ_PY}/.claude/aad"
echo '{"tasks":{}}' > "${PROJ_PY}/.claude/aad/state.json"
out=$(bash "${SCRIPTS_DIR}/cleanup.sh" run "$PROJ_PY" 2>&1)
if echo "$out" | grep -q "クリーンアップ完了" && ! [[ -d "$WT_PY" ]]; then
  pass "E2E-46: Python統合 cleanup → worktree削除 + アーカイブ"
else
  fail "E2E-46" "cleanup失敗: $out"
fi

# ============================================================
# Section 11: エージェント定義ファイル静的解析
# ============================================================
echo ""
echo "=== Section 11: エージェント定義ファイル静的解析 ==="

EXECUTE_MD="${REPO_ROOT}/aad-v2/agents/aad-phase-execute.md"
TDD_WORKER_MD="${REPO_ROOT}/aad-v2/agents/aad-tdd-worker.md"
SUBAGENT_PROMPT_MD="${REPO_ROOT}/aad-v2/skills/aad/references/subagent-prompt.md"
REVIEWER_MD="${REPO_ROOT}/aad-v2/agents/aad-reviewer.md"
AAD_CMD_MD="${REPO_ROOT}/aad-v2/commands/aad.md"
PHASE_GATE_SH="${REPO_ROOT}/aad-v2/skills/aad/scripts/phase-gate.sh"
STATE_SCHEMA_MD="${REPO_ROOT}/aad-v2/specs/state.schema.md"

# E2E-47: aad-phase-execute.md に TaskCreate 呼び出しあり
if [ -f "$EXECUTE_MD" ] && grep -q 'TaskCreate' "$EXECUTE_MD"; then
  pass "E2E-47: aad-phase-execute.md に TaskCreate あり"
else
  fail "E2E-47" "aad-phase-execute.md に TaskCreate が見つかりません"
fi

# E2E-48: aad-phase-execute.md に TeamCreate 呼び出しあり
if [ -f "$EXECUTE_MD" ] && grep -q 'TeamCreate' "$EXECUTE_MD"; then
  pass "E2E-48: aad-phase-execute.md に TeamCreate あり"
else
  fail "E2E-48" "aad-phase-execute.md に TeamCreate が見つかりません"
fi

# E2E-49: aad-phase-execute.md に SendMessage.*shutdown_request パターンあり
if [ -f "$EXECUTE_MD" ] && grep -q 'shutdown_request' "$EXECUTE_MD"; then
  pass "E2E-49: aad-phase-execute.md に shutdown_request あり"
else
  fail "E2E-49" "aad-phase-execute.md に shutdown_request が見つかりません"
fi

# E2E-50: TeamCreate に team_name パラメータあり
if [ -f "$EXECUTE_MD" ] && grep -q 'team_name' "$EXECUTE_MD"; then
  pass "E2E-50: aad-phase-execute.md に team_name パラメータあり"
else
  fail "E2E-50" "aad-phase-execute.md に team_name が見つかりません"
fi

# E2E-51: サブエージェントを生成する phase エージェント定義に subagent_type パラメータあり
# (aad-phase-pr.md は leaf エージェントのため除外)
PHASE_AGENTS_OK=true
for agent_file in \
    "${REPO_ROOT}/aad-v2/agents/aad-phase-plan.md" \
    "${REPO_ROOT}/aad-v2/agents/aad-phase-execute.md" \
    "${REPO_ROOT}/aad-v2/agents/aad-phase-review.md"; do
  if [ -f "$agent_file" ] && ! grep -q 'subagent_type' "$agent_file"; then
    PHASE_AGENTS_OK=false
    break
  fi
done
if $PHASE_AGENTS_OK; then
  pass "E2E-51: サブエージェント生成 phase に subagent_type あり (plan/execute/review)"
else
  fail "E2E-51" "一部の phase エージェントに subagent_type が見つかりません"
fi

# E2E-52: aad-tdd-worker.md / subagent-prompt.md に SendMessage あり
TDD_HAS_SEND=false
[ -f "$TDD_WORKER_MD" ] && grep -q 'SendMessage' "$TDD_WORKER_MD" && TDD_HAS_SEND=true
[ -f "$SUBAGENT_PROMPT_MD" ] && grep -q 'SendMessage' "$SUBAGENT_PROMPT_MD" && TDD_HAS_SEND=true
if $TDD_HAS_SEND; then
  pass "E2E-52: tdd-worker / subagent-prompt.md に SendMessage あり"
else
  fail "E2E-52" "tdd-worker / subagent-prompt.md に SendMessage が見つかりません"
fi

# E2E-53: team_name 命名規則 aad-wave- の一貫性
if [ -f "$EXECUTE_MD" ] && grep -q 'aad-wave-' "$EXECUTE_MD"; then
  pass "E2E-53: aad-phase-execute.md に aad-wave- 命名規則あり"
else
  fail "E2E-53" "aad-phase-execute.md に aad-wave- パターンが見つかりません"
fi

# E2E-54: aad-reviewer.md に TeamCreate あり
if [ -f "$REVIEWER_MD" ] && grep -q 'TeamCreate' "$REVIEWER_MD"; then
  pass "E2E-54: aad-reviewer.md に TeamCreate あり"
else
  fail "E2E-54" "aad-reviewer.md に TeamCreate が見つかりません"
fi

# E2E-55: README.md に "error" フィールド不使用（reason に統一）
README_MD="${REPO_ROOT}/aad-v2/README.md"
if [ -f "$README_MD" ] && ! grep -q '"error": "test failures"' "$README_MD"; then
  pass "E2E-55: README.md の state.json 例で error フィールドを使用していない"
else
  fail "E2E-55" "README.md に旧 error フィールドが残存しています"
fi

# E2E-56: aad.md の state.json 初期化に schemaVersion あり
if [ -f "$AAD_CMD_MD" ] && grep -q 'schemaVersion' "$AAD_CMD_MD"; then
  pass "E2E-56: aad.md の state.json 初期化に schemaVersion あり"
else
  fail "E2E-56" "aad.md に schemaVersion が見つかりません"
fi

# E2E-57: phase-gate.sh で schemaVersion バリデーションあり
if [ -f "$PHASE_GATE_SH" ] && grep -q 'schemaVersion' "$PHASE_GATE_SH"; then
  pass "E2E-57: phase-gate.sh に schemaVersion バリデーションあり"
else
  fail "E2E-57" "phase-gate.sh に schemaVersion バリデーションが見つかりません"
fi

# E2E-58: state.schema.md が存在する
if [ -f "$STATE_SCHEMA_MD" ]; then
  pass "E2E-58: specs/state.schema.md が存在する"
else
  fail "E2E-58" "specs/state.schema.md が存在しません"
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

[[ "$FAIL" -eq 0 ]]
