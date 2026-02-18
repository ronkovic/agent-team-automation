---
name: aad:plan
description: Generate implementation plan from requirements and create Wave-based task structure
requires_approval: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, WebSearch
output_language: japanese
---

# Implementation Plan Generation

**IMPORTANT**: Always output responses to users in Japanese.

<background_information>
- **Mission**: Analyze requirements and generate Wave-based parallel implementation plan
- **Success Criteria**:
  - Parse input source successfully
  - Analyze existing codebase structure
  - Create dependency-based Wave分割
  - Assign optimal models to agents (opus/sonnet/haiku)
  - Generate valid plan.json
  - Display plan summary for user approval
</background_information>

<instructions>
## Core Task
Generate implementation plan with Wave分割 and agent assignments from input requirements.

## Arguments
- `$1`: `<input-source>` - Input source (file path, directory, kiro spec, or text)

## Input Source Types

### 1. File Path
- Read file content directly
- Supported formats: `.md`, `.txt`, `.yaml`, `.json`

### 2. Directory Path
- Recursively read `.md`, `.yaml`, `.json` files
- Combine all content for analysis

### 3. Kiro Spec
- If path contains `.kiro/specs/`, auto-detect kiro spec
- Read `requirements.md` + `design.md` + `tasks.md`
- Use structured spec format

### 4. Plain Text
- If not file/directory, treat as direct text input
- Useful for quick requirements

## Execution Steps

### 1. Read Config
- Read `.claude/aad/project-config.json`
- Get project directory, worktree directory, parent branch

### 2. Parse Input Source
- Determine input type (file/directory/kiro/text)
- Read and combine content
- Extract key requirements

### 2.5 Codebase Investigation (Parallel Agents)

For large codebases, spawn 2-3 parallel investigation agents:

```
if codebase has 50+ files:
  Spawn in parallel:
  - Task(name: "investigator-structure", prompt: "Analyze project structure, dependencies, existing patterns")
  - Task(name: "investigator-tests", prompt: "Analyze existing test coverage, test patterns, test framework")
  - Task(name: "investigator-interfaces", prompt: "Identify public interfaces, shared types, API contracts")

  Collect and synthesize results before proceeding to Step 3
```

### 2.8 Generate Requirements Specification

Create `.claude/aad/requirements.md` with:

```markdown
# 実装仕様書

## 概要
{high-level description of what will be implemented}

## 現状分析
{current state of the codebase, existing patterns}

## 実装仕様
{detailed implementation specification per feature}

## 影響分析
{components affected, potential side effects}

## テストケース
{key test scenarios to cover}

## 実装ガイドライン
{coding conventions, patterns to follow, things to avoid}
```

### 3. Scan Existing Codebase
- Detect project structure patterns:
  - `src/`, `lib/`, `app/` (source code)
  - `tests/`, `__tests__/` (test files)
  - Package files: `package.json`, `pyproject.toml`, `go.mod`, etc.
- Identify programming language
- List existing modules/files
- Detect frameworks and libraries

### 4. Analyze Dependencies
- Parse requirements for task dependencies
- Identify shared code (core models, interfaces)
- Determine independent vs dependent tasks
- Detect circular dependencies (error if found)

### 5. Wave分割 (Wave Division)

**Wave 0 (Bootstrap)**:
- Shared code (core models, interfaces, types)
- Common utilities
- Configuration files
- Executed sequentially by team-lead

**Wave 1+ (Parallel)**:
- Independent tasks (no dependencies)
- Dependent tasks (grouped by dependency level)
- Integration tasks (combine results)
- Each Wave executes in parallel within itself

**Wave Criteria**:
- Tasks in same Wave have no dependencies on each other
- Tasks depend only on previous Wave completions
- Optimize for maximum parallelism
- Consider file conflicts (avoid concurrent edits to same file)

### 6. Model Assignment

Analyze task complexity and assign appropriate model:

**opus** (highest capability):
- Financial/trading logic requiring precision
- Complex algorithm implementation
- Critical business logic
- Multi-step reasoning tasks
- Integration of multiple components

**sonnet** (balanced):
- Standard API integrations
- Async/concurrent design
- Test implementation
- Data processing
- Common business logic

**haiku** (fast for simple tasks):
- Boilerplate code
- Configuration files
- Following existing patterns
- Simple CRUD operations
- Type definitions

### 7. Generate plan.json

Structure:
```json
{
  "featureName": "auth-feature",
  "waves": [
    {
      "id": 0,
      "type": "bootstrap",
      "tasks": [
        {
          "description": "Create core models",
          "files": ["src/models/order.py", "src/models/portfolio.py"]
        }
      ]
    },
    {
      "id": 1,
      "type": "parallel",
      "agents": [
        {
          "name": "agent-order",
          "model": "sonnet",
          "branch": "feature/order",
          "tasks": ["Implement order management"],
          "files": ["src/order.py", "tests/test_order.py"],
          "dependsOn": [],
          "test_cases": [
            "注文作成の正常系",
            "無効な注文量のバリデーション",
            "在庫不足エラー処理"
          ],
          "affected_components": ["OrderService", "OrderRepository", "OrderValidator"]
        },
        {
          "name": "agent-portfolio",
          "model": "opus",
          "branch": "feature/portfolio",
          "tasks": ["Implement portfolio tracking"],
          "files": ["src/portfolio.py", "tests/test_portfolio.py"],
          "dependsOn": [],
          "test_cases": [],
          "affected_components": []
        }
      ],
      "mergeOrder": ["agent-order", "agent-portfolio"]
    },
    {
      "id": 2,
      "type": "parallel",
      "agents": [
        {
          "name": "agent-integration",
          "model": "sonnet",
          "branch": "feature/integration",
          "tasks": ["Integrate order and portfolio"],
          "files": ["src/trading.py", "tests/test_trading.py"],
          "dependsOn": ["agent-order", "agent-portfolio"],
          "test_cases": [],
          "affected_components": []
        }
      ],
      "mergeOrder": ["agent-integration"]
    }
  ],
  "createdAt": "2026-02-18T00:00:00.000Z",
  "status": "pending_approval"
}
```

### Step 10: Validate plan.json

Run validation if scripts directory available:
```bash
if [ -n "${SCRIPTS_DIR:-}" ] && [ -f "${SCRIPTS_DIR}/plan.sh" ]; then
  ${SCRIPTS_DIR}/plan.sh validate .claude/aad/plan.json
fi
```

### 8. Generate state.json

Initial state:
```json
{
  "currentWave": 0,
  "completedWaves": [],
  "agentStatus": {},
  "mergeLog": [],
  "updatedAt": "2026-02-18T00:00:00.000Z"
}
```

### 9. Display Plan Summary (in Japanese)

Format:
```markdown
# 実装計画サマリー

## 概要
- 全Wave数: 3
- 全エージェント数: 3
- 全タスク数: 5
- 対象ファイル数: 6

## Wave構成

### Wave 0 (Bootstrap) - リーダー逐次実行
- コアモデル作成
- インターフェース定義
- 共通ユーティリティ

### Wave 1 (Parallel) - 2エージェント並列実行
**agent-order** (sonnet):
- タスク: オーダー管理実装
- ファイル: src/order.py, tests/test_order.py

**agent-portfolio** (opus):
- タスク: ポートフォリオ追跡実装
- ファイル: src/portfolio.py, tests/test_portfolio.py

### Wave 2 (Parallel) - 1エージェント
**agent-integration** (sonnet):
- タスク: オーダーとポートフォリオの統合
- ファイル: src/trading.py, tests/test_trading.py
- 依存: agent-order, agent-portfolio

## 承認
この計画で実行してよろしいですか？
承認する場合は `/aad:execute` を実行してください。
計画を修正する場合は `/aad:plan` を再実行してください。
```

## Important Constraints
- Detect and prevent circular dependencies
- Ensure Wave 0 contains only shared code
- Avoid file conflicts (same file in multiple agents)
- Balance agent workload
- Prefer parallelism but respect dependencies
</instructions>

## Tool Guidance
- Use **Read** to read requirements and existing files
- Use **Glob** to scan codebase structure
- Use **Grep** to search for specific patterns
- Use **Write** to create plan.json and state.json
- Use **Bash** for:
  - File counting
  - Dependency analysis scripts
  - ISO8601 timestamp generation
- Use **WebSearch** if external documentation needed (rarely)

## Safety & Fallback
- **No Config**: If project-config.json not found:
  ```
  エラー: プロジェクトが初期化されていません
  '/aad:init' コマンドでプロジェクトを初期化してください
  ```
- **Invalid Input**: If input source invalid:
  ```
  エラー: 入力ソースを読み込めません: <source>
  ファイルパス、ディレクトリ、またはテキストを指定してください
  ```
- **Circular Dependencies**: If detected:
  ```
  エラー: 循環依存を検出しました
  タスク間の依存関係を見直してください
  ```
- **No Tasks**: If no implementable tasks found:
  ```
  警告: 実装可能なタスクが見つかりませんでした
  要件を確認してください
  ```
