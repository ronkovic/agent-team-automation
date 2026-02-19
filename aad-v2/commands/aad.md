---
description: AAD v2 — Wave-based parallel TDD implementation. Runs init→plan→execute→review→PR→cleanup pipeline.
argument-hint: "[project-dir] <input-source> [parent-branch] [--dry-run] [--skip-review] [--keep-worktrees] [--workers N] [--spec-only]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TeamCreate, SendMessage, TeamDelete
---

# AAD v2 Orchestrator

**IMPORTANT**: Always output responses in Japanese.

## Step 0: スクリプトディレクトリ検出

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)/aad-v2}"
SCRIPTS_DIR="${AAD_SCRIPTS_DIR:-${PLUGIN_ROOT}/skills/aad/scripts}"
if [ ! -f "${SCRIPTS_DIR}/deps.sh" ]; then
  echo "⚠ deps.sh が見つかりません。インラインフォールバックを使用します。"
  SCRIPTS_DIR=""
fi
```

## Step 1: 引数パース

`$ARGUMENTS` を解析:

```bash
SKIP_REVIEW="${AAD_SKIP_REVIEW:-false}"
DRY_RUN=false; KEEP_WORKTREES=false; SPEC_ONLY=false; WORKERS="${AAD_WORKERS:-3}"
PROJECT_DIR="."; INPUT_SOURCE=""; PARENT_BRANCH="aad/develop"

ARGS=($ARGUMENTS)
i=0
while [ $i -lt ${#ARGS[@]} ]; do
  case "${ARGS[$i]}" in
    --skip-review)    SKIP_REVIEW=true ;;
    --dry-run)        DRY_RUN=true ;;
    --keep-worktrees) KEEP_WORKTREES=true ;;
    --spec-only)      SPEC_ONLY=true ;;
    --workers)        i=$((i+1)); WORKERS="${ARGS[$i]}" ;;
    *)
      arg="${ARGS[$i]}"
      if [ -z "$INPUT_SOURCE" ]; then
        if { [[ "$arg" == /* ]] || [[ "$arg" == ./* ]] || [[ "$arg" == ../* ]] || [ -d "$arg" ]; } \
           && [ -z "$INPUT_SOURCE" ]; then
          PROJECT_DIR="$arg"
        else
          INPUT_SOURCE="$arg"
        fi
      elif [ "$PARENT_BRANCH" = "aad/develop" ]; then
        PARENT_BRANCH="$arg"
      else
        echo "⚠ 不明な引数を無視しました: $arg" >&2
      fi ;;
  esac
  i=$((i+1))
done

export AAD_SKIP_REVIEW="$SKIP_REVIEW"
```

**INPUT_SOURCE 未指定チェック**:
```bash
if [ -z "$INPUT_SOURCE" ]; then
  echo "エラー: input-source が指定されていません" >&2
  echo "使用方法: /aad [project-dir] <input-source> [parent-branch] [options]" >&2
  echo "例: /aad requirements.md" >&2
  exit 1
fi
```

**引数なし**: 使用方法を表示して終了:
```
使用方法: /aad [project-dir] <input-source> [parent-branch] [options]
例: /aad requirements.md
例: /aad .kiro/specs/auth-feature --skip-review
例: /aad ./my-project requirements.md aad/develop
```

## Phase 1: 初期化（インライン）

### 1a: feature-name を導出

```bash
if [ -d "$INPUT_SOURCE" ]; then
  FEATURE_NAME=$(basename "${INPUT_SOURCE%/}")
elif [ -f "$INPUT_SOURCE" ]; then
  FEATURE_NAME=$(basename "$INPUT_SOURCE" | sed 's/\.[^.]*$//')
else
  FEATURE_NAME="unnamed"
fi
FEATURE_NAME=$(echo "$FEATURE_NAME" | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9-]/-/g' | sed 's/-\+/-/g' | sed 's/^-\|-$//g')
```

### 1b: Git 初期化

```bash
cd "$PROJECT_DIR"
[ ! -d ".git" ] && git init && echo "✓ git init 完了"
```

### 1c: 親ブランチ作成

```bash
git rev-parse --verify "$PARENT_BRANCH" >/dev/null 2>&1 \
  || git branch "$PARENT_BRANCH"
git checkout "$PARENT_BRANCH" 2>/dev/null || git checkout -b "$PARENT_BRANCH"
```

### 1d: Worktree ディレクトリ作成

```bash
WORKTREE_DIR="${PROJECT_DIR}-${FEATURE_NAME}-wt"
if [ -n "$SCRIPTS_DIR" ]; then
  ${SCRIPTS_DIR}/worktree.sh create-parent "$PROJECT_DIR" "$PARENT_BRANCH" "$FEATURE_NAME"
else
  mkdir -p "$WORKTREE_DIR"
fi
```

### 1e: state.json 初期化

```bash
RUN_ID=$(date +%Y%m%d-%H%M%S)
mkdir -p "${PROJECT_DIR}/.claude/aad"
cat > "${PROJECT_DIR}/.claude/aad/state.json" <<STATEEOF
{
  "runId": "${RUN_ID}",
  "currentLevel": 0,
  "completedLevels": [],
  "tasks": {},
  "mergeLog": [],
  "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
STATEEOF
```

### 1f: project-config.json 作成

```bash
ABS_PROJECT=$(cd "$PROJECT_DIR" && pwd)
cat > "${PROJECT_DIR}/.claude/aad/project-config.json" <<CFGEOF
{
  "projectDir": "${ABS_PROJECT}",
  "worktreeDir": "${ABS_PROJECT}-${FEATURE_NAME}-wt",
  "featureName": "${FEATURE_NAME}",
  "parentBranch": "${PARENT_BRANCH}",
  "runId": "${RUN_ID}",
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "initialized"
}
CFGEOF
```

表示:
```
## Phase 1: 初期化完了
✓ Feature: {feature-name} | Branch: {parent-branch} | Run: {RUN_ID}
```

### フェーズゲート: post-init

```bash
if [ -n "$SCRIPTS_DIR" ] && [ -f "${SCRIPTS_DIR}/phase-gate.sh" ]; then
  bash "${SCRIPTS_DIR}/phase-gate.sh" post-init "$PROJECT_DIR" \
    || { echo "✗ Phase 1 ゲート失敗。実行を中止します。" >&2; exit 1; }
fi
```

## Phase 2: 計画生成 (via aad-phase-plan)

```
Task(
  name: "aad-phase-plan",
  subagent_type: "aad-phase-plan",
  prompt: """
  PROJECT_DIR: {PROJECT_DIR}
  INPUT_SOURCE: {INPUT_SOURCE}
  PARENT_BRANCH: {PARENT_BRANCH}
  SCRIPTS_DIR: {SCRIPTS_DIR}
  WORKERS: {WORKERS}
  DRY_RUN: {DRY_RUN}
  SPEC_ONLY: {SPEC_ONLY}
  CLAUDE_PLUGIN_ROOT: {PLUGIN_ROOT}
  """
)
```

完了後、plan-output.json を読む:

```bash
PLAN_OUTPUT="${PROJECT_DIR}/.claude/aad/phases/plan-output.json"
if command -v jq >/dev/null 2>&1; then
  WAVE_COUNT=$(jq '.waveCount // "?"' "$PLAN_OUTPUT" 2>/dev/null || echo "?")
  AGENT_COUNT=$(jq '.agentCount // "?"' "$PLAN_OUTPUT" 2>/dev/null || echo "?")
else
  WAVE_COUNT=$(python3 -c "import json; d=json.load(open('$PLAN_OUTPUT')); print(d.get('waveCount', '?'))" 2>/dev/null || echo "?")
  AGENT_COUNT=$(python3 -c "import json; d=json.load(open('$PLAN_OUTPUT')); print(d.get('agentCount', '?'))" 2>/dev/null || echo "?")
fi
```

`--dry-run` の場合: ここで終了。
`--spec-only` の場合: requirements.md 生成後に終了。

承認を求める:
```
## Phase 2: 計画生成完了
Wave数: {WAVE_COUNT} | エージェント数: {AGENT_COUNT}

この計画で実行を続けますか？ (y/N)
```

### フェーズゲート: post-plan

```bash
if [ -n "$SCRIPTS_DIR" ] && [ -f "${SCRIPTS_DIR}/phase-gate.sh" ]; then
  bash "${SCRIPTS_DIR}/phase-gate.sh" post-plan "$PROJECT_DIR" \
    || { echo "✗ Phase 2 ゲート失敗。計画が不正です。" >&2; exit 1; }
fi
```

## Phase 3: 実装実行 (via aad-phase-execute)

```
Task(
  name: "aad-phase-execute",
  subagent_type: "aad-phase-execute",
  prompt: """
  PROJECT_DIR: {PROJECT_DIR}
  WORKTREE_DIR: {WORKTREE_DIR}
  PARENT_BRANCH: {PARENT_BRANCH}
  SCRIPTS_DIR: {SCRIPTS_DIR}
  WORKERS: {WORKERS}
  SKIP_REVIEW: {SKIP_REVIEW}
  PLUGIN_ROOT: {PLUGIN_ROOT}
  """
)
```

完了後、execute-output.json を読む:

```bash
EXECUTE_OUTPUT="${PROJECT_DIR}/.claude/aad/phases/execute-output.json"
if command -v jq >/dev/null 2>&1; then
  INITIAL_REF=$(jq -r '.initialRef // empty' "$EXECUTE_OUTPUT" 2>/dev/null || echo "")
  COMMIT_COUNT=$(jq '.commitCount // "?"' "$EXECUTE_OUTPUT" 2>/dev/null || echo "?")
else
  INITIAL_REF=$(python3 -c "import json; d=json.load(open('$EXECUTE_OUTPUT')); print(d.get('initialRef', ''))" 2>/dev/null || echo "")
  COMMIT_COUNT=$(python3 -c "import json; d=json.load(open('$EXECUTE_OUTPUT')); print(d.get('commitCount', '?'))" 2>/dev/null || echo "?")
fi
```

表示: `## Phase 3: 実装実行完了 | コミット数: {COMMIT_COUNT}`

### フェーズゲート: post-execute

```bash
if [ -n "$SCRIPTS_DIR" ] && [ -f "${SCRIPTS_DIR}/phase-gate.sh" ]; then
  bash "${SCRIPTS_DIR}/phase-gate.sh" post-execute "$PROJECT_DIR" \
    || { echo "✗ Phase 3 ゲート失敗。実行に問題があります。" >&2; exit 1; }
fi
```

## Phase 4: 最終コードレビュー (via aad-phase-review)

`AAD_SKIP_REVIEW=true` でなければ実行:

```
Task(
  name: "aad-phase-review",
  subagent_type: "aad-phase-review",
  prompt: """
  PROJECT_DIR: {PROJECT_DIR}
  INITIAL_REF: {INITIAL_REF}
  SCRIPTS_DIR: {SCRIPTS_DIR}
  PLUGIN_ROOT: {PLUGIN_ROOT}
  """
)
```

完了後、review-output.json を読む:

```bash
REVIEW_OUTPUT="${PROJECT_DIR}/.claude/aad/phases/review-output.json"
if [ -f "$REVIEW_OUTPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    CRITICAL=$(jq '.critical // 0' "$REVIEW_OUTPUT" 2>/dev/null || echo "0")
    WARNING=$(jq '.warning // 0' "$REVIEW_OUTPUT" 2>/dev/null || echo "0")
    AUTO_FIXED=$(jq '.autoFixed // 0' "$REVIEW_OUTPUT" 2>/dev/null || echo "0")
  else
    CRITICAL=$(python3 -c "import json; d=json.load(open('$REVIEW_OUTPUT')); print(d.get('critical', 0))" 2>/dev/null || echo "0")
    WARNING=$(python3 -c "import json; d=json.load(open('$REVIEW_OUTPUT')); print(d.get('warning', 0))" 2>/dev/null || echo "0")
    AUTO_FIXED=$(python3 -c "import json; d=json.load(open('$REVIEW_OUTPUT')); print(d.get('autoFixed', 0))" 2>/dev/null || echo "0")
  fi
  echo "## Phase 4: 最終コードレビュー完了"
  echo "Critical: ${CRITICAL} | Warning: ${WARNING} | 自動修正: ${AUTO_FIXED}件"
fi
```

### フェーズゲート: post-review

```bash
if [ -n "$SCRIPTS_DIR" ] && [ -f "${SCRIPTS_DIR}/phase-gate.sh" ]; then
  bash "${SCRIPTS_DIR}/phase-gate.sh" post-review "$PROJECT_DIR" 2>/dev/null || true
  # post-review は警告のみ (exit 0 維持)
fi
```

## Phase 5: PR 作成 (via aad-phase-pr)

`gh` コマンドが利用可能かつ remote が存在する場合:

```
Task(
  name: "aad-phase-pr",
  subagent_type: "aad-phase-pr",
  prompt: """
  PROJECT_DIR: {PROJECT_DIR}
  INITIAL_REF: {INITIAL_REF}
  RUN_ID: {RUN_ID}
  PARENT_BRANCH: {PARENT_BRANCH}
  """
)
```

完了後、pr-output.json を読んで PR URL を表示。

## Phase 6: クリーンアップ（インライン）

`--keep-worktrees` でなければ:

```bash
if [ -n "$SCRIPTS_DIR" ]; then
  ${SCRIPTS_DIR}/cleanup.sh run "$PROJECT_DIR"
else
  git worktree prune
  git branch --list 'feature/*' | while IFS= read -r b; do
    git branch -D "${b#  }" 2>/dev/null || true
  done
fi
```

state.json アーカイブ:
```bash
ARCHIVE_DIR="${PROJECT_DIR}/.claude/aad/archive/${RUN_ID}"
mkdir -p "$ARCHIVE_DIR"
cp "${PROJECT_DIR}/.claude/aad/state.json" "${ARCHIVE_DIR}/" 2>/dev/null || true
cp "${PROJECT_DIR}/.claude/aad/plan.json"  "${ARCHIVE_DIR}/" 2>/dev/null || true
```

## 復旧フロー（エラー時）

state.json を読んで `status: "failed"` のタスクを特定:

```bash
jq '.tasks | to_entries[] | select(.value.status == "failed")' state.json
git log --oneline ${INITIAL_REF}..HEAD | grep "merge(wave"
```

失敗タスクのみ worktree 再作成・エージェント再 spawn。成功済みレベルはスキップ。

## 出力フォーマット

```markdown
# AAD v2 実行開始

## Phase 1: 初期化 ✓
✓ Feature: {name} | Branch: {branch} | Run: {run-id}

## Phase 2: 計画生成 ✓
Wave数: {N} | エージェント数: {M}

この計画で実行を続けますか？ (y/N):

## Phase 3: 実装実行
### Wave 0: Bootstrap ✓
### Wave 1: 並列実行 ({N}エージェント) ✓

## Phase 4: 最終コードレビュー ✓
Critical: 0 | Warning: 2 | 自動修正: 2件

## Phase 5: PR作成 ✓
Draft PR: {url}

## Phase 6: クリーンアップ ✓

# 完了
Wave数: {N} | エージェント数: {M} | コミット数: {K}
```

## 重要制約

- TDDサイクルを省略しない
- マージ順序（依存関係）を尊重する
- エージェント失敗時は state.json に記録して継続
- エラー時もリソースクリーンアップを実施
- `AAD_STRICT_TDD=true` 時、TDDサイクル未遵守をエラー扱い
- フェーズゲート失敗時は実行を中止（post-review のみ警告）
