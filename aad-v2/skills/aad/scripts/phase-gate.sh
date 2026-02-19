#!/usr/bin/env bash
# フェーズ間バリデーション（フェーズゲート）
# Usage: phase-gate.sh <gate> <project_dir>
# ゲート: post-init, post-plan, post-execute, post-review
set -euo pipefail

GATE="${1:?使用方法: phase-gate.sh <gate> <project_dir>}"
PROJECT_DIR="${2:?使用方法: phase-gate.sh <gate> <project_dir>}"
AAD_DIR="${PROJECT_DIR}/.claude/aad"

gate_pass() {
  echo "GATE PASS: $1"
  exit 0
}

gate_fail() {
  echo "GATE FAIL: $1" >&2
  exit 1
}

do_post_init() {
  [[ -f "${AAD_DIR}/state.json" ]] \
    || gate_fail "state.json が存在しません: ${AAD_DIR}/state.json"
  [[ -f "${AAD_DIR}/project-config.json" ]] \
    || gate_fail "project-config.json が存在しません: ${AAD_DIR}/project-config.json"

  if command -v jq >/dev/null 2>&1; then
    jq -e '.runId' "${AAD_DIR}/state.json" >/dev/null 2>&1 \
      || gate_fail "state.json に runId がありません"
    jq -e '.projectDir' "${AAD_DIR}/project-config.json" >/dev/null 2>&1 \
      || gate_fail "project-config.json に projectDir がありません"
  else
    python3 -c "
import json, sys
s = json.load(open(sys.argv[1]))
c = json.load(open(sys.argv[2]))
missing = []
if 'runId' not in s:
    missing.append('state.json:runId')
if 'projectDir' not in c:
    missing.append('project-config.json:projectDir')
if missing:
    print('必須フィールド欠落: ' + ', '.join(missing))
    sys.exit(1)
" "${AAD_DIR}/state.json" "${AAD_DIR}/project-config.json" \
      || gate_fail "必須フィールドが欠落しています"
  fi

  gate_pass "post-init"
}

do_post_plan() {
  [[ -f "${AAD_DIR}/plan.json" ]] \
    || gate_fail "plan.json が存在しません: ${AAD_DIR}/plan.json"

  # SCRIPTS_DIR 自動検出 (AAD_SCRIPTS_DIR 環境変数優先)
  local scripts_dir="${AAD_SCRIPTS_DIR:-}"
  if [[ -z "$scripts_dir" ]]; then
    local git_root
    git_root=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$git_root" ]]; then
      scripts_dir="${git_root}/aad-v2/skills/aad/scripts"
    fi
  fi

  if [[ -n "$scripts_dir" ]] && [[ -f "${scripts_dir}/plan.sh" ]]; then
    bash "${scripts_dir}/plan.sh" validate "${AAD_DIR}/plan.json" >/dev/null 2>&1 \
      || gate_fail "plan.json バリデーション失敗 (plan.sh validate)"
  fi

  local wave_count
  if command -v jq >/dev/null 2>&1; then
    wave_count=$(jq '.waves | length' "${AAD_DIR}/plan.json" 2>/dev/null || echo "0")
  else
    wave_count=$(python3 -c "
import json
d = json.load(open('${AAD_DIR}/plan.json'))
print(len(d.get('waves', [])))" 2>/dev/null || echo "0")
  fi

  [[ "$wave_count" -gt 0 ]] \
    || gate_fail "plan.json に wave が定義されていません (wave数: ${wave_count})"

  gate_pass "post-plan"
}

do_post_execute() {
  local lock_file="${AAD_DIR}/aad-merge.lock"
  [[ ! -f "$lock_file" ]] \
    || gate_fail "マージロックが残存しています: ${lock_file}"

  [[ -f "${AAD_DIR}/state.json" ]] \
    || gate_fail "state.json が存在しません: ${AAD_DIR}/state.json"

  local failed_count
  if command -v jq >/dev/null 2>&1; then
    failed_count=$(jq '[.tasks // {} | to_entries[] | select(.value.status == "failed")] | length' \
      "${AAD_DIR}/state.json" 2>/dev/null || echo "0")
  else
    failed_count=$(python3 -c "
import json
d = json.load(open('${AAD_DIR}/state.json'))
tasks = d.get('tasks', {})
print(sum(1 for v in tasks.values() if isinstance(v, dict) and v.get('status') == 'failed'))" \
      2>/dev/null || echo "0")
  fi

  [[ "$failed_count" -eq 0 ]] \
    || gate_fail "失敗タスクが ${failed_count} 件あります"

  gate_pass "post-execute"
}

do_post_review() {
  local review_file="${AAD_DIR}/phases/review-output.json"

  # review-output.json が存在しなければスキップ (PASS)
  if [[ ! -f "$review_file" ]]; then
    gate_pass "post-review (review-output.json なし — スキップ)"
  fi

  local critical
  if command -v jq >/dev/null 2>&1; then
    critical=$(jq '.critical // 0' "$review_file" 2>/dev/null || echo "0")
  else
    critical=$(python3 -c "
import json
d = json.load(open('${review_file}'))
print(d.get('critical', 0))" 2>/dev/null || echo "0")
  fi

  if [[ "$critical" -gt 0 ]]; then
    echo "⚠ WARN: critical issues ${critical} 件 — 要確認" >&2
    # exit 0 (警告のみ、ブロックしない)
  fi

  gate_pass "post-review"
}

case "$GATE" in
  post-init)    do_post_init ;;
  post-plan)    do_post_plan ;;
  post-execute) do_post_execute ;;
  post-review)  do_post_review ;;
  *)
    echo "エラー: 不明なゲート: ${GATE}" >&2
    echo "使用可能: post-init, post-plan, post-execute, post-review" >&2
    exit 1
    ;;
esac
