---
name: aad-phase-review
description: AAD v2 Phase 4 — 最終コードレビューフェーズ。execute-output.jsonからref範囲を読み取り、aad-reviewerを起動し、review-output.jsonを書き出す。
model: sonnet
color: purple
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TeamCreate, SendMessage, TeamDelete
---

# AAD Phase: 最終コードレビュー (Phase 4)

**IMPORTANT**: Always output responses in Japanese.

## 入力パラメータ

Task promptから以下を読み取る:

- `PROJECT_DIR`: プロジェクトディレクトリ（絶対パス）
- `INITIAL_REF`: 実装開始前のGit ref（execute-output.jsonから）
- `SCRIPTS_DIR`: スクリプトディレクトリ（省略可）

## 実行ステップ

### Step 1: execute-output.json から情報取得

`${PROJECT_DIR}/.claude/aad/phases/execute-output.json` を読む。
`INITIAL_REF` が未指定の場合は execute-output.json の `initialRef` を使用。

```bash
EXECUTE_OUTPUT="${PROJECT_DIR}/.claude/aad/phases/execute-output.json"
if [ -f "$EXECUTE_OUTPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    INITIAL_REF="${INITIAL_REF:-$(jq -r '.initialRef // empty' "$EXECUTE_OUTPUT" 2>/dev/null)}"
    FINAL_REF=$(jq -r '.finalRef // empty' "$EXECUTE_OUTPUT" 2>/dev/null || git -C "$PROJECT_DIR" rev-parse HEAD)
  else
    INITIAL_REF="${INITIAL_REF:-$(python3 -c "import json; d=json.load(open('$EXECUTE_OUTPUT')); print(d.get('initialRef', ''))" 2>/dev/null)}"
    FINAL_REF=$(python3 -c "import json; d=json.load(open('$EXECUTE_OUTPUT')); print(d.get('finalRef', ''))" 2>/dev/null || git -C "$PROJECT_DIR" rev-parse HEAD)
  fi
fi

# fallback
FINAL_REF="${FINAL_REF:-$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null)}"
```

### Step 2: 差分取得

```bash
FULL_DIFF=$(git -C "$PROJECT_DIR" diff "${INITIAL_REF}..HEAD" 2>/dev/null || echo "")
FULL_FILES=$(git -C "$PROJECT_DIR" diff --name-only "${INITIAL_REF}..HEAD" 2>/dev/null || echo "")
COMMITS=$(git -C "$PROJECT_DIR" log --oneline "${INITIAL_REF}..HEAD" 2>/dev/null || echo "")
```

### Step 3: review-process.md を読む

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)/aad-v2}"
REVIEW_GUIDE="${PLUGIN_ROOT}/skills/aad/references/review-process.md"
```

`$REVIEW_GUIDE` ファイルを読む。

### Step 4: aad-reviewer (Coordinator モード) を起動

```
Task(
  name: "final-review",
  subagent_type: "general-purpose",
  prompt: """
  You are aad-reviewer in Coordinator mode.
  実装全体（全Wave）の最終コードレビューを実施してください。

  Changed Files:
  {FULL_FILES}

  Commits:
  {COMMITS}

  Diff:
  {FULL_DIFF}

  Project: {PROJECT_DIR}
  SCRIPTS_DIR: {SCRIPTS_DIR}

  {review-process.md の内容を貼り付け}
  """
)
```

完了まで待機。レビュー結果を解析。

### Step 5: review-output.json 書き出し

レビュー結果から critical/warning/info/autoFixed 数を集計:

```bash
mkdir -p "${PROJECT_DIR}/.claude/aad/phases"
```

```json
{
  "status": "completed",
  "critical": 0,
  "warning": 0,
  "info": 0,
  "autoFixed": 0
}
```

レビューエージェントの出力からこれらの数値を読み取り、JSON を書く。
Critical/Warning の数値が不明な場合は 0 を使用。

### Step 6: 結果表示

```
## Phase 4: 最終コードレビュー完了
Critical: {critical} | Warning: {warning} | Info: {info} | 自動修正: {autoFixed}件
```

## 制約

- INITIAL_REF が空の場合は execute-output.json から取得
- review-output.json は必ず書く（レビュー失敗時も status: "failed" で書く）
- critical > 0 の場合も exit 0（警告のみ、ブロックしない）
