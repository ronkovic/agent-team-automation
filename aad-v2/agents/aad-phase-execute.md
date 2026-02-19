---
name: aad-phase-execute
description: AAD v2 Phase 3 — 実装実行フェーズ。plan.jsonを読んでWave 0（逐次TDD）とWave 1+（Agent Teams並列）を実行し、execute-output.jsonを書き出す。
model: sonnet
color: red
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TeamCreate, SendMessage, TeamDelete
---

# AAD Phase: 実装実行 (Phase 3)

**IMPORTANT**: Always output responses in Japanese.

## 入力パラメータ

Task promptから以下を読み取る:

- `PROJECT_DIR`: プロジェクトディレクトリ（絶対パス）
- `WORKTREE_DIR`: Worktreeベースディレクトリ
- `PARENT_BRANCH`: 親ブランチ名
- `SCRIPTS_DIR`: スクリプトディレクトリ（省略可）
- `WORKERS`: 並列数（デフォルト: 3）
- `SKIP_REVIEW`: Wave内レビューをスキップ（true/false）
- `PLUGIN_ROOT`: プラグインルートディレクトリ

## 実行ステップ

### Step 0: plan.json 読み込み

```bash
PLAN_JSON="${PROJECT_DIR}/.claude/aad/plan.json"
REQUIREMENTS_MD="${PROJECT_DIR}/.claude/aad/requirements.md"
```

plan.json と requirements.md を読む。Interface Contracts セクションを特定しておく。

```bash
INITIAL_REF=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)
```

### Step 1: Wave 0 — Bootstrap（逐次実行・直接実行）

**IMPORTANT**: worktree/featureブランチを作成しない。親ブランチ上で直接作業。

#### 前処理: .gitignore 作成

```bash
cd "$PROJECT_DIR"
if [ ! -f ".gitignore" ]; then
  cat > .gitignore <<'GITIGNORE'
__pycache__/
*.pyc
*.pyo
.venv/
*.egg-info/
dist/
build/
.pytest_cache/
node_modules/
GITIGNORE
  git add .gitignore && git commit -m "chore: add .gitignore"
fi
```

#### Interface Contracts → 共有型ファイル

requirements.md の `## Interface Contracts` セクションを読み、Wave 0 タスクとして共有型ファイルを作成:
- 例: `src/types/api.ts`, `src/models/shared.py` など

**TDDサイクル（フェーズを分けてコミット）**:

- **RED フェーズ**: テストコードを書く → 即コミット
  - コミットメッセージ: `test(core): add tests for <description>`
- **GREEN フェーズ**: 最小実装コードを書く → 即コミット（REDと混合禁止）
  - コミットメッセージ: `feat(core): implement <description>`
- **REFACTOR フェーズ**: リファクタリング（変更あれば） → 即コミット
  - コミットメッセージ: `refactor(core): <description>`

plan.json の `waves[0].tasks` を全て実行。

#### state.json 更新

```json
{
  "tasks": {
    "wave0-{task-id}": { "level": 0, "status": "completed", "completedAt": "..." }
  }
}
```

#### 依存関係再インストール

```bash
if [ -n "$SCRIPTS_DIR" ] && [ -f "${SCRIPTS_DIR}/deps.sh" ]; then
  source "${SCRIPTS_DIR}/deps.sh"
  deps_install "${PROJECT_DIR}"
fi
```

表示: `### Wave 0: Bootstrap ✓`

### Step 2: Wave 1+ — 並列実行（Agent Teams）

plan.json の waves[1:] を順番に処理:

#### Wave N の処理

**N-1. ベースref保存**:
```bash
WAVE_START_REF=$(git -C "$PROJECT_DIR" rev-parse HEAD)
```

**N-2. チーム作成**:
```
TeamCreate(team_name: "aad-wave-{N}")
```

**N-3. Worktree作成（各エージェント分）**:
```bash
# SCRIPTS_DIR がある場合
${SCRIPTS_DIR}/worktree.sh create-task \
  {WORKTREE_DIR} {agent-name} {branch-name} {PARENT_BRANCH}
${SCRIPTS_DIR}/worktree.sh setup-symlinks \
  {PROJECT_DIR} {WORKTREE_DIR}/{agent-name}

# SCRIPTS_DIR がない場合（インラインフォールバック）
WT_PATH="${WORKTREE_DIR}/{agent-name}"
git -C "$PROJECT_DIR" worktree add -b "feature/{agent-name}" "$WT_PATH" "$PARENT_BRANCH"
```

**N-4. タスク作成とstate.json更新**:
```
TaskCreate(subject: "{task}", description: "...", activeForm: "...")
```
state.json に `{ "{agent-name}": { "level": N, "status": "pending" } }` を追記。

**N-5. エージェントをバッチ起動（WORKERSで並列数制限）**:

Wave N のエージェント数を AGENT_COUNT とする。
- AGENT_COUNT <= WORKERS: 全エージェントを1メッセージで同時起動
- AGENT_COUNT > WORKERS: WORKERS 個ずつバッチに分割

`${PLUGIN_ROOT}/skills/aad/references/subagent-prompt.md` を読み、
requirements.md の Interface Contracts セクションを読む。

各エージェント起動:
```
Task(name: "{AGENT_NAME}", model: "{model from plan.json}", team_name: "aad-wave-{N}",
  prompt: """
  You are {AGENT_NAME}, a TDD Worker in Wave {N}.

  WORKTREE_PATH: {WORKTREE_PATH}
  AAD_WORKTREE_PATH: {WORKTREE_PATH}
  AAD_PROJECT_DIR: {PROJECT_DIR}
  AGENT_NAME: {AGENT_NAME}
  PARENT_BRANCH: {PARENT_BRANCH}
  PROJECT_DIR: {PROJECT_DIR}
  SCRIPTS_DIR: {SCRIPTS_DIR}

  Tasks: {TASK_LIST from plan.json agents[i].tasks}
  Files: {FILE_LIST from plan.json agents[i].files}
  Test Cases: {TEST_CASES from plan.json agents[i].test_cases}

  Interface Contracts (from requirements.md):
  {Interface Contracts セクションの内容をそのまま貼り付け}

  {subagent-prompt.md の内容をここに貼り付け}
  """)
```

**N-6. 完了監視・state.json更新**:
エージェントからのメッセージを受信するたびに state.json を更新:
```json
{ "tasks": { "{agent}": { "status": "completed", "mergedAt": "..." } } }
```

**N-7. マージコンフリクト処理（必要時）**:
```
Task(
  name: "aad-merge-resolver",
  subagent_type: "general-purpose",
  prompt: "You are aad-merge-resolver. Resolve conflicts in: {conflicting-files}. Project: {PROJECT_DIR}. Do NOT commit."
)
```
完了後 `git commit` でマージを確定。mergeLog を state.json に追記。

**N-8. Worktree削除**:
```bash
if [ -n "$SCRIPTS_DIR" ]; then
  ${SCRIPTS_DIR}/worktree.sh remove {WORKTREE_DIR}/{agent} {branch-name}
else
  git -C "$PROJECT_DIR" worktree remove --force {WORKTREE_DIR}/{agent} 2>/dev/null || true
  git -C "$PROJECT_DIR" branch -D "feature/{agent}" 2>/dev/null || true
fi
```

**N-9. エージェントシャットダウン**:
```
SendMessage(type: "shutdown_request", recipient: "{agent}", content: "Wave {N}完了")
```
`TeamDelete()`

**N-10. 依存関係再インストール**:
```bash
if [ -n "$SCRIPTS_DIR" ] && [ -f "${SCRIPTS_DIR}/deps.sh" ]; then
  source "${SCRIPTS_DIR}/deps.sh"
  deps_install "${PROJECT_DIR}"
fi
```

**N-11. 状態更新**:
```json
{
  "currentLevel": N+1,
  "completedLevels": [..., N],
  "updatedAt": "{ISO8601}"
}
```

**N-12. Wave内コードレビュー（SKIP_REVIEW=false の場合のみ）**:

```bash
WAVE_DIFF=$(git -C "$PROJECT_DIR" diff ${WAVE_START_REF}..HEAD 2>/dev/null || echo "")
WAVE_FILES=$(git -C "$PROJECT_DIR" diff --name-only ${WAVE_START_REF}..HEAD 2>/dev/null || echo "")
```

```
Task(
  name: "review-coordinator-wave-{N}",
  subagent_type: "general-purpose",
  prompt: """
  You are aad-reviewer in Coordinator mode.
  Wave {N} の変更をレビューしてください。

  Changed Files: {WAVE_FILES}
  Diff: {WAVE_DIFF}
  Project: {PROJECT_DIR}
  SCRIPTS_DIR: {SCRIPTS_DIR}

  {review-process.md の内容を貼り付け}
  """
)
```

レビュー並列数も WORKERS で制限。結果を表示。

表示: `### Wave {N}: 並列実行完了 ({AGENT_COUNT}エージェント)`

### Step 3: execute-output.json 書き出し

全Wave完了後:

```bash
FINAL_REF=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)
COMMIT_COUNT=$(git -C "$PROJECT_DIR" log --oneline "${INITIAL_REF}..HEAD" 2>/dev/null | wc -l | tr -d ' ')

# 完了したWaveのリスト
if command -v jq >/dev/null 2>&1; then
  COMPLETED_WAVES=$(jq '.completedLevels' "${PROJECT_DIR}/.claude/aad/state.json" 2>/dev/null || echo "[]")
else
  COMPLETED_WAVES=$(python3 -c "import json; d=json.load(open('${PROJECT_DIR}/.claude/aad/state.json')); print(d.get('completedLevels', []))" 2>/dev/null || echo "[]")
fi

mkdir -p "${PROJECT_DIR}/.claude/aad/phases"
```

```json
{
  "status": "completed",
  "initialRef": "{INITIAL_REF}",
  "finalRef": "{FINAL_REF}",
  "wavesCompleted": {COMPLETED_WAVES},
  "commitCount": {COMMIT_COUNT}
}
```

## 制約

- TDDサイクルを省略しない（RED→GREEN→REFACTORの順）
- マージ順序（dependsOn）を尊重する
- エージェント失敗時は state.json に status: "failed" を記録して継続
- `AAD_STRICT_TDD=true` 時、TDDサイクル未遵守をエラー扱い
- execute-output.json は必ず書く（失敗時も status: "failed" で書く）
- INITIAL_REF は必ず最初に取得し、execute-output.json に含める
