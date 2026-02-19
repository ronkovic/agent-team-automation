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
        # is_path: / or ./ or ../ または既存ディレクトリ
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

## Phase 1: 初期化

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
mkdir -p "$WORKTREE_DIR"
```

または:
```bash
if [ -n "$SCRIPTS_DIR" ]; then
  ${SCRIPTS_DIR}/worktree.sh create-parent "$PROJECT_DIR" "$PARENT_BRANCH" "$FEATURE_NAME"
fi
```

### 1e: state.json 初期化（タスク単位・3層ハイブリッド）

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

```json
{
  "projectDir": "{abs-path}",
  "worktreeDir": "{abs-path}-{feature-name}-wt",
  "featureName": "{feature-name}",
  "parentBranch": "{branch}",
  "runId": "{RUN_ID}",
  "createdAt": "{ISO8601}",
  "status": "initialized"
}
```

表示:
```
## Phase 1: 初期化完了
✓ Feature: {feature-name} | Branch: {parent-branch} | Worktree: {worktree-dir}
```

## Phase 2: 計画生成

### 2a: 依存関係インストール

```bash
if [ -n "$SCRIPTS_DIR" ]; then
  source "${SCRIPTS_DIR}/deps.sh"
  deps_install "${PROJECT_DIR}"
else
  # インラインフォールバック（deps.shが利用できない場合）
  [ -f "package.json" ] && command -v npm >/dev/null 2>&1 && npm install
  [ -f "go.mod" ] && command -v go >/dev/null 2>&1 && go mod download
  if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
    command -v uv >/dev/null 2>&1 \
      && { uv venv .venv 2>/dev/null || true; uv pip install --python .venv/bin/python pytest; } \
      || python3 -m pip install --user pytest 2>/dev/null || true
  fi
fi
```

### 2b: aad-planner エージェントを起動

```
Task(
  name: "aad-planner",
  subagent_type: "general-purpose",
  prompt: """
  You are aad-planner. Generate implementation plan for this project.

  PROJECT_DIR: {PROJECT_DIR}
  INPUT_SOURCE: {INPUT_SOURCE}
  PARENT_BRANCH: {PARENT_BRANCH}

  Output:
  1. .claude/aad/requirements.md (with Interface Contracts section)
  2. .claude/aad/plan.json (Wave-based structure)
  3. Display plan summary in Japanese for user approval

  [Follow aad-planner agent instructions]
  """
)
```

待機。planner完了後 plan.json と requirements.md を読む。

### 2c: 計画表示・ユーザー承認

Wave構成・エージェント数・Interface Contractsを日本語で表示。
`--dry-run` の場合: ここで終了。
`--spec-only` の場合: requirements.md生成後に終了。

承認を求める:
```
この計画で実行を続けますか？ (y/N)
```

## Phase 3: 実行

### ベースラインref保存

```bash
INITIAL_REF=$(git -C "$PROJECT_DIR" rev-parse HEAD)
```

### Wave 0: Bootstrap（逐次実行・team-lead直接）

**IMPORTANT**: worktree/featureブランチを作成しない。親ブランチ上で直接作業。

**前処理**:
```bash
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

**Interface Contracts → 共有型ファイル**:
requirements.md の Interface Contracts セクションを読み、Wave 0 タスクとして
共有型ファイルを作成（例: `src/types/api.ts`, `src/models/shared.py`）。

**TDDサイクル（フェーズを分けてコミット）**:
- RED: `test(core): add tests for <description>` → 即コミット
- GREEN: `feat(core): implement <description>` → 即コミット（REDと混合禁止）
- REFACTOR: `refactor(core): <description>` → 変更あれば即コミット

**state.json 更新（タスクごと）**:
```json
{
  "tasks": {
    "wave0-{task-id}": { "level": 0, "status": "completed", "completedAt": "..." }
  }
}
```

**Wave 0 完了後に依存関係を再インストール**（新しいmanifestが生成された可能性）:
```bash
deps_install "${PROJECT_DIR}"  # または同等のインラインコマンド
```

### Wave 1+: 並列実行（Agent Teams）

**Wave N ごとの処理**:

**N-1.** ベースref保存:
```bash
WAVE_START_REF=$(git -C "$PROJECT_DIR" rev-parse HEAD)
```

**N-2.** チーム作成:
```
TeamCreate(team_name: "aad-wave-{N}")
```

**N-3.** Worktree作成（symlink付き）:
```bash
${SCRIPTS_DIR}/worktree.sh create-task \
  {WORKTREE_DIR} {agent-name} {branch-name} {PARENT_BRANCH}

# 共有依存をsymlink（dist/build/は除外）
${SCRIPTS_DIR}/worktree.sh setup-symlinks \
  {PROJECT_DIR} {WORKTREE_DIR}/{agent-name}
```

**N-4.** タスク作成とstate.json更新:
```
TaskCreate(subject: "{task}", description: "...", activeForm: "...")
```
```json
{
  "tasks": { "{agent-name}": { "level": N, "status": "pending" } }
}
```

**N-5.** エージェントをバッチ起動（WORKERSで並列数制限）:

Wave N のエージェント数を AGENT_COUNT とする。

- AGENT_COUNT <= WORKERS: 全エージェントを1メッセージで同時起動（従来通り）
- AGENT_COUNT > WORKERS: WORKERS 個ずつバッチに分割して順次起動。
  各バッチの全エージェントが完了（メッセージ受信 or shutdown）してから次バッチを起動。
  バッチ内のエージェントは1メッセージで同時起動。

例: WORKERS=3, エージェント5体 → Batch1: 3体同時, Batch2: 2体同時

```
Task(name: "{AGENT_NAME}", model: "{MODEL}", team_name: "aad-wave-{N}",
  prompt: """
  You are {AGENT_NAME}, a TDD Worker in Wave {N}.

  WORKTREE_PATH: {WORKTREE_PATH}
  AAD_WORKTREE_PATH: {WORKTREE_PATH}
  AGENT_NAME: {AGENT_NAME}
  PARENT_BRANCH: {PARENT_BRANCH}
  PROJECT_DIR: {PROJECT_DIR}
  SCRIPTS_DIR: {SCRIPTS_DIR}

  Tasks: {TASK_LIST from plan.json}
  Files: {FILE_LIST from plan.json}
  Test Cases: {TEST_CASES from plan.json}

  Interface Contracts (from requirements.md):
  {paste Interface Contracts section verbatim}

  {paste content of skills/aad/references/subagent-prompt.md}
  """)

Task(name: "{agent-2}", ...)
...
```

**N-6.** 完了監視・state.json更新:
エージェントからのメッセージを受信するたびに:
```json
{ "tasks": { "{agent}": { "status": "completed", "mergedAt": "..." } } }
```

**N-7.** マージコンフリクト処理（必要時）:
```
Task(
  name: "aad-merge-resolver",
  subagent_type: "general-purpose",
  prompt: "You are aad-merge-resolver. Resolve conflicts in: {conflicting-files}. Project: {PROJECT_DIR}. Do NOT commit."
)
```
完了後 `git commit` でマージを確定。mergeLog を state.json に追記。

**N-8.** Worktree削除:
```bash
${SCRIPTS_DIR}/worktree.sh remove {WORKTREE_DIR}/{agent} {branch-name}
```

**N-9.** エージェントシャットダウン:
```
SendMessage(type: "shutdown_request", recipient: "{agent}", content: "Wave {N}完了")
```
`TeamDelete()`

**N-10.** 依存関係再インストール（mergeで新manifest追加の可能性）:
```bash
deps_install "${PROJECT_DIR}"
```

**N-11.** 状態更新:
```json
{
  "currentLevel": N+1,
  "completedLevels": [..., N]
}
```

**N-12.** Wave内コードレビュー（`AAD_SKIP_REVIEW=true` でなければ）。レビュー並列数も WORKERS で制限する:
```bash
WAVE_DIFF=$(git -C "$PROJECT_DIR" diff ${WAVE_START_REF}..HEAD)
WAVE_FILES=$(git -C "$PROJECT_DIR" diff --name-only ${WAVE_START_REF}..HEAD)
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

  {paste content of skills/aad/references/review-process.md}
  """
)
```
結果を表示。

## Phase 4: 最終コードレビュー

全Wave完了後（`AAD_SKIP_REVIEW=true` でなければ）:

```bash
FULL_DIFF=$(git -C "$PROJECT_DIR" diff ${INITIAL_REF}..HEAD)
FULL_FILES=$(git -C "$PROJECT_DIR" diff --name-only ${INITIAL_REF}..HEAD)
COMMITS=$(git -C "$PROJECT_DIR" log --oneline ${INITIAL_REF}..HEAD)
```

```
Task(
  name: "final-review",
  subagent_type: "general-purpose",
  prompt: """
  You are aad-reviewer in Coordinator mode.
  実装全体（全Wave）の最終コードレビューを実施してください。

  Changed Files: {FULL_FILES}
  Commits: {COMMITS}
  Diff: {FULL_DIFF}
  Project: {PROJECT_DIR}
  SCRIPTS_DIR: {SCRIPTS_DIR}

  {paste content of skills/aad/references/review-process.md}
  """
)
```

## Phase 5: PR 作成

`gh` コマンドが利用可能かつ remote が存在する場合:

```bash
WAVE_COUNT=$(jq '.completedLevels | length' "${PROJECT_DIR}/.claude/aad/state.json" 2>/dev/null || echo "?")
AGENT_COUNT=$(jq '.tasks | length' "${PROJECT_DIR}/.claude/aad/state.json" 2>/dev/null || echo "?")
COMMIT_COUNT=$(git -C "$PROJECT_DIR" log --oneline ${INITIAL_REF}..HEAD | wc -l | tr -d ' ')
FEATURE_TITLE=$(jq -r '.featureName // "implementation"' "${PROJECT_DIR}/.claude/aad/plan.json" 2>/dev/null)

git -C "$PROJECT_DIR" push -u origin "$PARENT_BRANCH" 2>/dev/null || true

gh pr create --draft \
  --title "feat: ${FEATURE_TITLE}" \
  --body "$(cat <<'PREOF'
## 実装サマリー — AAD v2

### 統計
- Wave数: ${WAVE_COUNT}
- エージェント数: ${AGENT_COUNT}
- コミット数: ${COMMIT_COUNT}

### 実装内容
{plan.json の tasks サマリー}

### コードレビュー
{最終レビュー結果のサマリー}

---
*Generated by /aad (aad-v2 ${RUN_ID})*
PREOF
)"
echo "✓ Draft PR作成完了"
```

## Phase 6: クリーンアップ

`--keep-worktrees` でなければ:

```bash
if [ -n "$SCRIPTS_DIR" ]; then
  # cleanup.sh run が内部で worktree.sh cleanup を呼ぶため二重呼び出し不要
  ${SCRIPTS_DIR}/cleanup.sh run "$PROJECT_DIR"
else
  git worktree prune
  git branch --list 'feature/*' | while IFS= read -r b; do
    git branch -D "${b#  }" 2>/dev/null || true
  done
fi
```

state.jsonアーカイブ:
```bash
ARCHIVE_DIR="${PROJECT_DIR}/.claude/aad/archive/${RUN_ID}"
mkdir -p "$ARCHIVE_DIR"
cp "${PROJECT_DIR}/.claude/aad/state.json" "${ARCHIVE_DIR}/"
cp "${PROJECT_DIR}/.claude/aad/plan.json"  "${ARCHIVE_DIR}/"
```

## 復旧フロー（エラー時）

state.json を読んで `status: "failed"` のタスクを特定:

```bash
# 失敗タスクの確認
jq '.tasks | to_entries[] | select(.value.status == "failed")' state.json

# git logと照合（実際にマージ済みのコミットを確認）
git log --oneline ${INITIAL_REF}..HEAD | grep "merge(wave"
```

失敗タスクのみ worktree 再作成・エージェント再 spawn。
成功済みレベルはスキップ。最初の未完了レベルから再開。

## 出力フォーマット

```markdown
# AAD v2 実行開始

## Phase 1: 初期化 ✓
✓ Feature: {name} | Branch: {branch} | Run: {run-id}

## Phase 2: 計画生成 ✓
Wave数: {N} | エージェント数: {M} | ファイル数: {K}

### Interface Contracts
| Method | Path | Request | Response |
...

この計画で実行を続けますか？ (y/N):

## Phase 3: 実装実行

### Wave 0: Bootstrap ✓
✓ コアモデル作成 | ✓ 共有型ファイル作成

### Wave 1: 並列実行 (2エージェント)
✓ agent-order 完了 (3コミット) | ✓ agent-portfolio 完了 (4コミット)
✓ マージ完了 | ✓ Waveレビュー: Critical 0, Warning 1

## Phase 4: 最終コードレビュー ✓
Critical: 0 | Warning: 2 | Info: 5 | 自動修正: 2件

## Phase 5: PR作成 ✓
Draft PR: {url}

## Phase 6: クリーンアップ ✓

# 完了
Wave数: {N} | エージェント数: {M} | コミット数: {K} | 実行時間: {T}分
```

## 重要制約

- TDDサイクルを省略しない
- マージ順序（依存関係）を尊重する
- エージェント失敗時は state.json に記録して継続
- エラー時もリソースクリーンアップを実施
- `AAD_STRICT_TDD=true` 時、TDDサイクル未遵守をエラー扱い
