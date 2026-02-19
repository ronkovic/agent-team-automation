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

### Step 3: review-process.md を読み込む

```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)/aad-v2}"
REVIEW_GUIDE="${PLUGIN_ROOT}/skills/aad/references/review-process.md"
REVIEW_PROCESS=$(cat "$REVIEW_GUIDE" 2>/dev/null || echo "")
```

### Step 4: aad-reviewer (Coordinator モード) を起動

```
Task(
  name: "final-review",
  subagent_type: "aad-reviewer",
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

  ${REVIEW_PROCESS}
  """
)
```

完了まで待機。レビュー結果を解析。

### Step 5: review-output.json 書き出し

レビュー結果から構造化サマリーJSONブロックを抽出:

```bash
# レビュー結果テキストから JSON ブロックを抽出
REVIEW_RESULT="<aad-reviewer の返答テキスト>"

if command -v python3 >/dev/null 2>&1; then
  REVIEW_COUNTS=$(echo "$REVIEW_RESULT" | python3 -c "
import sys, json, re
text = sys.stdin.read()
# \`\`\`json ... \`\`\` ブロックから最後のJSONを抽出
matches = re.findall(r'\`\`\`json\s*\n({.*?})\s*\n\`\`\`', text, re.DOTALL)
if matches:
    d = json.loads(matches[-1])
    print(json.dumps({
        'critical': d.get('critical', 0),
        'warning': d.get('warning', 0),
        'info': d.get('info', 0),
        'autoFixed': d.get('autoFixed', 0)
    }))
else:
    print(json.dumps({'critical': 0, 'warning': 0, 'info': 0, 'autoFixed': 0}))
" 2>/dev/null)
else
  # フォールバック: Critical: N パターンをgrep
  CRITICAL=$(echo "$REVIEW_RESULT" | grep -oE 'Critical: [0-9]+' | grep -oE '[0-9]+' | tail -1 || echo "0")
  WARNING=$(echo "$REVIEW_RESULT" | grep -oE 'Warning: [0-9]+' | grep -oE '[0-9]+' | tail -1 || echo "0")
  INFO=$(echo "$REVIEW_RESULT" | grep -oE 'Info: [0-9]+' | grep -oE '[0-9]+' | tail -1 || echo "0")
  REVIEW_COUNTS="{\"critical\":${CRITICAL:-0},\"warning\":${WARNING:-0},\"info\":${INFO:-0},\"autoFixed\":0}"
fi
```

抽出した値で review-output.json を書く:

```bash
mkdir -p "${PROJECT_DIR}/.claude/aad/phases"
echo "$REVIEW_COUNTS" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
d['status'] = 'completed'
json.dump(d, open('${PROJECT_DIR}/.claude/aad/phases/review-output.json', 'w'), indent=2)
" 2>/dev/null
```

抽出に失敗した場合はフォールバック:

```json
{"status": "completed", "critical": 0, "warning": 0, "info": 0, "autoFixed": 0}
```

### Step 6: 結果表示

```
## Phase 4: 最終コードレビュー完了
Critical: {critical} | Warning: {warning} | Info: {info} | 自動修正: {autoFixed}件
```

## 制約

- INITIAL_REF が空の場合は execute-output.json から取得
- review-output.json は必ず書く（レビュー失敗時も status: "failed" で書く）
- 構造化サマリー JSON が抽出できない場合は全カウントを 0 とする
- review-output.json の critical/warning/info は reviewer の構造化サマリーから取得
