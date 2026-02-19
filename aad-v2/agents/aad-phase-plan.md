---
name: aad-phase-plan
description: AAD v2 Phase 2 — 計画生成フェーズ。依存関係インストール→aad-planner起動→plan-output.json書き出し。aad.mdディスパッチャーからTask()で起動される。
model: sonnet
color: green
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task
---

# AAD Phase: 計画生成 (Phase 2)

**IMPORTANT**: Always output responses in Japanese.

## 入力パラメータ

Task promptから以下の変数を読み取る:

- `PROJECT_DIR`: プロジェクトディレクトリ（絶対パス）
- `INPUT_SOURCE`: 要件ファイル/ディレクトリ/テキスト
- `PARENT_BRANCH`: 親ブランチ名（例: aad/develop）
- `SCRIPTS_DIR`: スクリプトディレクトリ（省略可、空の場合はインラインフォールバック）
- `WORKERS`: 並列数（省略可、デフォルト: 3）
- `DRY_RUN`: ドライラン（true/false）
- `SPEC_ONLY`: 仕様のみ（true/false）

## 実行ステップ

### Step 1: 依存関係インストール

SCRIPTS_DIR が利用可能な場合は retry.sh でラップ:

```bash
if [ -n "$SCRIPTS_DIR" ] && [ -f "${SCRIPTS_DIR}/retry.sh" ] && [ -f "${SCRIPTS_DIR}/deps.sh" ]; then
  bash "${SCRIPTS_DIR}/retry.sh" --max 3 --delay 5 --backoff -- \
    bash "${SCRIPTS_DIR}/deps.sh" install "$PROJECT_DIR"
elif [ -n "$SCRIPTS_DIR" ] && [ -f "${SCRIPTS_DIR}/deps.sh" ]; then
  source "${SCRIPTS_DIR}/deps.sh"
  deps_install "${PROJECT_DIR}"
else
  # インラインフォールバック
  cd "$PROJECT_DIR"
  [ -f "package.json" ] && command -v npm >/dev/null 2>&1 && npm install --silent 2>/dev/null || true
  [ -f "go.mod" ] && command -v go >/dev/null 2>&1 && go mod download 2>/dev/null || true
  if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
    command -v uv >/dev/null 2>&1 \
      && { uv venv .venv 2>/dev/null || true; uv pip install --python .venv/bin/python pytest 2>/dev/null || true; } \
      || python3 -m pip install --user pytest 2>/dev/null || true
  fi
fi
```

### Step 2: aad-planner エージェントを起動

`PLUGIN_ROOT` を特定:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)/aad-v2}"
```

aad-planner の指示ファイルを読み込む:

```bash
PLANNER_PROMPT=$(cat "${PLUGIN_ROOT}/agents/aad-planner.md" 2>/dev/null || echo "")
```

以下のプロンプトで aad-planner を起動:

```
Task(
  name: "aad-planner",
  subagent_type: "aad-planner",
  prompt: """
  You are aad-planner. Generate implementation plan for this project.

  PROJECT_DIR: {PROJECT_DIR}
  INPUT_SOURCE: {INPUT_SOURCE}
  PARENT_BRANCH: {PARENT_BRANCH}
  SCRIPTS_DIR: {SCRIPTS_DIR}
  CLAUDE_PLUGIN_ROOT: {PLUGIN_ROOT}

  ${PLANNER_PROMPT}
  """
)
```

完了まで待機。

### Step 3: plan-output.json 書き出し

aad-planner 完了後、plan.json と requirements.md を確認:

```bash
PLAN_PATH="${PROJECT_DIR}/.claude/aad/plan.json"
REQ_PATH="${PROJECT_DIR}/.claude/aad/requirements.md"
```

wave数とエージェント数を取得:

```bash
if command -v jq >/dev/null 2>&1; then
  WAVE_COUNT=$(jq '.waves | length' "$PLAN_PATH" 2>/dev/null || echo "0")
  AGENT_COUNT=$(jq '[.waves[] | .agents // [] | .[]] | length' "$PLAN_PATH" 2>/dev/null || echo "0")
else
  WAVE_COUNT=$(python3 -c "import json; d=json.load(open('$PLAN_PATH')); print(len(d.get('waves', [])))" 2>/dev/null || echo "0")
  AGENT_COUNT=$(python3 -c "import json; d=json.load(open('$PLAN_PATH')); print(sum(len(w.get('agents', [])) for w in d.get('waves', [])))" 2>/dev/null || echo "0")
fi
```

出力ディレクトリを作成し、plan-output.json を書く:

```bash
mkdir -p "${PROJECT_DIR}/.claude/aad/phases"
```

```json
{
  "status": "completed",
  "planPath": ".claude/aad/plan.json",
  "requirementsPath": ".claude/aad/requirements.md",
  "waveCount": WAVE_COUNT,
  "agentCount": AGENT_COUNT
}
```

### Step 4: 結果表示

```
## Phase 2: 計画生成完了
Wave数: {WAVE_COUNT} | エージェント数: {AGENT_COUNT}
```

`DRY_RUN=true` または `SPEC_ONLY=true` の場合は、その旨を表示して終了。

## 制約

- aad-planner が plan.json を書かない場合はエラー
- plan.json が存在しない場合は exit 1
- 出力は必ず `.claude/aad/phases/plan-output.json` に書く
