---
name: aad:execute
description: Execute Wave-based implementation plan with parallel agent teams
requires_approval: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TeamCreate, SendMessage, TeamDelete
output_language: japanese
---

# Wave-Based Execution

**IMPORTANT**: Always output responses to users in Japanese.

<background_information>
- **Mission**: Execute Wave-based implementation plan with parallel agent teams
- **Success Criteria**:
  - Execute Wave 0 (bootstrap) sequentially
  - Execute Wave 1+ with parallel agents
  - Create worktrees for each agent
  - Monitor agent completion
  - Merge in specified order
  - Cleanup worktrees after merge
  - Update state tracking
  - Complete all Waves successfully
</background_information>

<instructions>
## Core Task
Execute implementation plan Wave by Wave with parallel agent teams.

## Arguments
- `$1`: `[wave-number]` - Specific Wave to execute (optional, default: all Waves sequentially)

## Execution Flow

### Phase 1: Load Plan

#### Step 0: Detect Scripts Directory (Required First)

Detect the location of shell scripts **before anything else**:
```bash
if [ -n "${AAD_SCRIPTS_DIR:-}" ]; then
  SCRIPTS_DIR="$AAD_SCRIPTS_DIR"
elif [ -f "$(git rev-parse --show-toplevel)/scripts/worktree.sh" ]; then
  SCRIPTS_DIR="$(git rev-parse --show-toplevel)/scripts"
else
  # **Last resort**: inline git commands only when scripts/worktree.sh is not found
  SCRIPTS_DIR=""
  echo "警告: scripts/worktree.sh が見つかりません。インラインgitコマンドで代用します。"
fi
```

**IMPORTANT**: Pass `SCRIPTS_DIR` to all agent prompts in Step 4.

1. Read `.claude/aad/plan.json`
2. Read `.claude/aad/state.json` (or create if not exists)
3. Determine Waves to execute (specific Wave or all pending)
4. Verify plan status is valid

### Phase 1.5: Install Dependencies

Before executing any Wave, install project dependencies to ensure test runners are available:
```bash
# Python: uv で仮想環境を作成（pip3/python3 バージョン不一致を回避）
if [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
  if command -v uv >/dev/null 2>&1; then
    uv venv .venv 2>/dev/null || true  # 既存の場合はスキップ
    UV_INSTALL="uv pip install --python .venv/bin/python"
    if [ -f "pyproject.toml" ] && grep -q '\[.*test\]' pyproject.toml 2>/dev/null; then
      $UV_INSTALL -e ".[dev]" 2>/dev/null || $UV_INSTALL -e ".[test]" 2>/dev/null || $UV_INSTALL pytest
    elif [ -f "requirements.txt" ]; then
      $UV_INSTALL -r requirements.txt
    else
      $UV_INSTALL pytest
    fi
    PYTHON=".venv/bin/python"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user pytest 2>/dev/null || true
    PYTHON="python3"
  else
    echo "⚠ 警告: python3/uv がインストールされていません。Pythonテストはスキップされます。"
  fi
  echo "Python実行環境: ${PYTHON:-未検出}"
fi

# Node.js / TypeScript
if [ -f "package.json" ]; then
  if command -v npm >/dev/null 2>&1; then
    npm install
  else
    echo "⚠ 警告: npm がインストールされていません。Node.js/TypeScriptのビルドとテストはスキップされます。"
  fi
fi

# Go
if [ -f "go.mod" ]; then
  if command -v go >/dev/null 2>&1; then
    go mod download
  else
    echo "⚠ 警告: go がインストールされていません。Goのビルドとテストはスキップされます。"
  fi
fi

# Rust
if [ -f "Cargo.toml" ]; then
  if command -v cargo >/dev/null 2>&1; then
    cargo fetch 2>/dev/null || true
  else
    echo "⚠ 警告: cargo がインストールされていません。Rustのビルドとテストはスキップされます。"
  fi
fi

# Ruby
if [ -f "Gemfile" ]; then
  if command -v bundle >/dev/null 2>&1; then
    bundle install
  else
    echo "⚠ 警告: bundle がインストールされていません。Rubyの依存解決とテストはスキップされます。"
  fi
fi

# Java (Maven / Gradle)
if [ -f "pom.xml" ]; then
  if command -v mvn >/dev/null 2>&1; then
    mvn dependency:resolve -q
  else
    echo "⚠ 警告: mvn がインストールされていません。Javaのビルドとテストはスキップされます。"
  fi
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  if command -v gradle >/dev/null 2>&1; then
    gradle dependencies --quiet 2>/dev/null || true
  else
    echo "⚠ 警告: gradle がインストールされていません。Javaのビルドとテストはスキップされます。"
  fi
fi
```

**IMPORTANT**: Pass the resolved `$PYTHON` path to all agent prompts so agents use the same interpreter.

### Phase 2: Execute Wave 0 (Bootstrap)

**IMPORTANT: Wave 0 does NOT use a worktree or feature branch.**
Work directly on the parent branch ({parentBranch}) in the main project directory.
**Do NOT create a worktree. Do NOT create a feature branch. Do NOT spawn agents.**

**Sequential execution by team-lead**:

**Before starting TDD cycle, create `.gitignore` if it does not exist**:
```bash
if [ ! -f .gitignore ]; then
  cat > .gitignore << 'GITIGNORE'
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

**After Wave 0 completes, re-install dependencies for any newly created manifest files**:
```bash
# Python
if [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
  if command -v uv >/dev/null 2>&1; then
    uv venv .venv 2>/dev/null || true
    UV_INSTALL="uv pip install --python .venv/bin/python"
    if [ -f "pyproject.toml" ] && grep -q '\[.*test\]' pyproject.toml 2>/dev/null; then
      $UV_INSTALL -e ".[dev]" 2>/dev/null || $UV_INSTALL -e ".[test]" 2>/dev/null || $UV_INSTALL pytest
    elif [ -f "requirements.txt" ]; then
      $UV_INSTALL -r requirements.txt
    else
      $UV_INSTALL pytest
    fi
    PYTHON=".venv/bin/python"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user pytest 2>/dev/null || true
    PYTHON="python3"
  fi
fi

# Node.js / TypeScript
if [ -f "package.json" ]; then
  if command -v npm >/dev/null 2>&1; then
    npm install
  fi
fi

# Go
if [ -f "go.mod" ]; then
  if command -v go >/dev/null 2>&1; then
    go mod download
  fi
fi

# Rust / Ruby / Java — same pattern as Phase 1.5 Step 0
```

1. Get Wave 0 tasks from plan.json
2. For each task in Wave 0, follow TDD cycle with **separate commits per phase**:
   - **RED**: Write failing tests first → **MUST commit NOW** (do not combine with GREEN):
     `test(core): add tests for <description>`
   - **GREEN**: Write minimum implementation to pass tests → **MUST commit NOW** (do not combine with RED):
     `feat(core): implement <description>`
   - **REFACTOR**: Improve code quality, verify tests still pass → commit if changed:
     `refactor(core): <description>`
3. **Install dependencies for newly created files** (MANDATORY — Wave 0 creates package.json / go.mod):
   ```bash
   cd {projectDir}

   # Frontend (package.json created in Wave 0)
   if [ -f "frontend/package.json" ] && [ ! -d "frontend/node_modules" ]; then
     (cd frontend && npm install)
   elif [ -f "package.json" ] && [ ! -d "node_modules" ]; then
     npm install
   fi

   # Backend (go.mod created in Wave 0)
   if [ -f "backend/go.mod" ] && command -v go >/dev/null 2>&1; then
     (cd backend && go mod download)
   elif [ -f "go.mod" ] && command -v go >/dev/null 2>&1; then
     go mod download
   fi
   ```
4. Mark Wave 0 as completed in state.json
5. Display Wave 0 completion summary

**Wave 0 Commit Convention** (separate commits per phase — do NOT combine):
```
test(core): add tests for <description>    ← RED phase commit
feat(core): implement <description>        ← GREEN phase commit
refactor(core): <description>             ← REFACTOR phase commit (if applicable)
```
**IMPORTANT: Never combine RED and GREEN into a single commit.**

### Phase 3: Execute Wave 1+ (Parallel)

For each Wave N (N >= 1):

**Save Wave baseline for post-Wave review**:
```bash
WAVE_START_REF=$(git rev-parse HEAD)
```

#### Step 1: Create Team
```
TeamCreate(
  team_name: "wave-{N}",
  description: "Wave {N} parallel implementation"
)
```

#### Step 2: Create Worktrees
For each agent in Wave:
```bash
# If SCRIPTS_DIR is available:
if [ -n "${SCRIPTS_DIR}" ]; then
  ${SCRIPTS_DIR}/worktree.sh create-task \
    {worktreeDir} \
    {agent-name} \
    {branch-name} \
    {parentBranch}
else
  # Inline fallback
  git worktree add \
    {worktreeDir}/{agent-name} \
    -b feature/{branch-name} \
    {parentBranch}
fi
```

Verify worktree creation and checkout.

#### Step 3: Create Tasks
For each agent:
```
TaskCreate(
  subject: "{agent task description}",
  description: "Implement: {tasks}\nFiles: {files}\nWorktree: {path}",
  activeForm: "Implementing {feature}"
)
```

Set dependencies if specified in plan.json.

#### Step 4: Spawn ALL Agents Simultaneously

**CRITICAL: Include ALL Task() calls in a SINGLE message. Do NOT batch or loop.**
All agents must be spawned in one response for true parallelism.

For each agent, embed the full tdd-worker instructions in the prompt:
```
Task(
  subagent_type: "general-purpose",
  team_name: "wave-{N}",
  name: "{agent-name}",
  model: "{opus|sonnet|haiku}",  # from plan.json
  prompt: """
    You are {agent-name} working on Wave {N} as a TDD Worker.

    **Working Directory**: {worktree-path}
    **Branch**: feature/{branch-name}
    **Parent Branch**: {parentBranch}
    **Project Directory**: {projectDir}
    **Scripts Directory**: {SCRIPTS_DIR}
    **Tasks**: {task-list}
    **Files**: {file-list}
    **Interface References**: {interface-files}
    **Dependencies**: {dependency-info}

    ## API Contract (Cross-Stack Parallel Agents)

    **If the current Wave has an `apiContract` field in plan.json**, inject its contents:
    - List each endpoint: method, path, request body, response, status codes
    - PATCH endpoints: emphasize "partial-update — only fields present in request body are updated, omitted fields retain current values"
    - Include errorFormat and sharedTypes definitions
    - You MUST follow this contract exactly. Do not deviate.

    **FALLBACK**: If `apiContract` exists at plan.json **root level** (incorrect position but still usable),
    inject the root-level contract into ALL waves that contain both frontend and backend agents.
    This ensures cross-stack agents receive the API contract even if plan generation placed it incorrectly.

    **If no `apiContract` is defined** (single-stack Wave), use fallback:
    - PATCH endpoints MUST use partial update semantics
    - Follow standard HTTP method semantics: POST=create, PUT=full replace, PATCH=partial update
    - Do NOT add required field validation for PATCH that rejects subset requests

    ## Setup (Before Starting Work)

    1. **Detect test framework** (if SCRIPTS_DIR is set):
       FRAMEWORK=$({SCRIPTS_DIR}/tdd.sh detect-framework {worktree-path})
       If SCRIPTS_DIR is empty, detect manually (pytest.ini → pytest, package.json → jest, go.mod → go test).

    2. **Verify worktree isolation**:
       pwd  # Must show {worktree-path}
       git branch --show-current  # Must show feature/{branch-name}

    ## TDD Cycle (MANDATORY — Do NOT skip any phase)

    ### 1. RED (Test Failure)
    - Write tests BEFORE any implementation
    - Tests must naturally fail at this stage
    - **MUST commit NOW** (do not combine with GREEN):
      test(<module>): add tests for <feature>
    - Auto-commit: {SCRIPTS_DIR}/tdd.sh commit-phase red <scope> <description> {worktree-path}

    ### 2. GREEN (Test Pass)
    - Write minimum implementation to pass tests only
    - No premature optimization or abstraction
    - Verify all tests pass
    - **MUST commit NOW** (do not combine with RED):
      feat(<module>): implement <feature>
    - Auto-commit: {SCRIPTS_DIR}/tdd.sh commit-phase green <scope> <description> {worktree-path}

    ### 3. REFACTOR
    - Improve code quality (DRY, naming, structure)
    - Verify tests still pass after each change
    - Commit: refactor(<module>): <description>
    - Auto-commit: {SCRIPTS_DIR}/tdd.sh commit-phase review <scope> <description> {worktree-path}

    ### 4. REVIEW (Final Check)
    - Run full test suite: {SCRIPTS_DIR}/tdd.sh run-tests {worktree-path}
    - Check for regressions in existing tests
    - Add tests for uncovered edge cases

    ### 5. TEST QUALITY RULES
    - **Never inject mocks at module level** (e.g., `sys.modules[...] = mock`)
    - Use pytest fixtures (`monkeypatch`, `mock.patch`) scoped to individual tests
    - Each test file must be independently runnable: `pytest tests/test_foo.py`
    - Do NOT create stub/mock modules for code implemented by other agents

    ## Commit Convention (Conventional Commits)

    Format: <type>(<scope>): <description>
    - test: Add/modify tests
    - feat: New feature implementation
    - refactor: Refactoring without feature change
    - fix: Bug fix

    ## Self-Merge (After All Tasks Complete)

    {SCRIPTS_DIR}/tdd.sh merge-to-parent \
      {worktree-path} \
      {agent-name} \
      {parentBranch} \
      {projectDir}

    Uses spinlock (120s timeout) to safely serialize concurrent merges.
    Report merge result to team-lead via SendMessage.

    ## Completion Criteria

    All of the following must be met before marking task as completed:
    1. All tests pass
    2. No regression in existing tests
    3. TDD cycle completed (RED -> GREEN -> REFACTOR -> REVIEW)
    4. All commits follow Conventional Commits format
    5. Self-merge to {parentBranch} completed
    6. TaskUpdate with status=completed

    Work autonomously. Report only when complete or blocked.
  """
)
```

#### Step 5: Monitor Completion
- Wait for all agents to complete
- Receive completion messages from agents
- Check TaskList for remaining tasks
- Handle agent failures/blocks

#### Step 6: Agent Self-Merge (Spinlock-Based)

Agents merge themselves to parent branch using spinlock. Orchestrator monitors.

Each agent executes:
```bash
${SCRIPTS_DIR}/tdd.sh merge-to-parent \
  {worktree-path} \
  {agent-name} \
  {parentBranch} \
  {projectDir}
```

If merge conflict detected (non-lock files):
1. Spawn merge-resolver agent:
   ```
   Task(
     subagent_type: "general-purpose",
     prompt: "You are a merge conflict resolver. Run in {projectDir}.
              Use the merge-resolver agent definition.
              Resolve conflicts in: {conflicting-files}
              Do NOT commit."
   )
   ```
2. After resolver completes, run `git commit` to finalize merge
3. Update mergeLog in state.json

Note: Lock files (.lock) are auto-resolved with --theirs by tdd.sh

If SCRIPTS_DIR is empty (fallback):
Follow `mergeOrder` from plan.json:
```bash
cd {projectDir}
git checkout {parentBranch}
git merge --no-ff feature/{branch-name} \
  -m "merge(wave-{N}): {agent-description}"
```

Update mergeLog in state.json:
```json
{
  "branch": "feature/{branch}",
  "agent": "{agent-name}",
  "wave": N,
  "mergedAt": "{ISO8601}",
  "commits": count
}
```

#### Step 7: Cleanup Worktrees
For each agent after successful merge:
```bash
if [ -n "${SCRIPTS_DIR}" ]; then
  ${SCRIPTS_DIR}/worktree.sh remove {worktreeDir}/{agent-name} {branch-name}
else
  # Inline fallback with --force retry
  git worktree remove {worktreeDir}/{agent-name} 2>/dev/null \
    || git worktree remove --force {worktreeDir}/{agent-name} 2>/dev/null \
    || rm -rf {worktreeDir}/{agent-name}
  git worktree prune
  git branch -d feature/{branch-name} 2>/dev/null || true
fi
```

#### Step 8: Shutdown Agents
For each agent:
```
SendMessage(
  type: "shutdown_request",
  recipient: "{agent-name}",
  content: "Wave {N} complete, thank you"
)
```

Wait for shutdown approval.

#### Step 9: Delete Team
```
TeamDelete()
```

#### Step 10: Update State & Reinstall Dependencies

**10a** Update state.json:
```json
{
  "currentWave": N + 1,
  "completedWaves": [..., N],
  "agentStatus": {
    "{agent-name}": {
      "status": "completed",
      "commits": count,
      "wave": N
    }
  },
  "updatedAt": "{ISO8601}"
}
```

**10b** Reinstall dependencies in {projectDir} (MANDATORY — each Wave merge may introduce new manifest files):
```bash
cd {projectDir}

# Check frontend/
if [ -f "frontend/package.json" ] && [ ! -d "frontend/node_modules" ]; then
  (cd frontend && npm install)
elif [ -f "package.json" ] && [ ! -d "node_modules" ]; then
  npm install
fi

# Check backend/
if [ -f "backend/go.mod" ] && command -v go >/dev/null 2>&1; then
  (cd backend && go mod download)
elif [ -f "go.mod" ] && command -v go >/dev/null 2>&1; then
  go mod download
fi

# Python
if [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
  if command -v uv >/dev/null 2>&1; then
    uv venv .venv 2>/dev/null || true
    UV_INSTALL="uv pip install --python .venv/bin/python"
    if [ -f "pyproject.toml" ] && grep -q '\[.*test\]' pyproject.toml 2>/dev/null; then
      $UV_INSTALL -e ".[dev]" 2>/dev/null || $UV_INSTALL -e ".[test]" 2>/dev/null || $UV_INSTALL pytest
    elif [ -f "requirements.txt" ]; then
      $UV_INSTALL -r requirements.txt
    else
      $UV_INSTALL pytest
    fi
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --user pytest 2>/dev/null || true
  fi
fi
```

#### Step 11: Wave Completion Report
Display Wave N summary:
```markdown
## Wave {N} 完了

### 実行サマリー
- エージェント数: X
- 実装ファイル数: Y
- コミット数: Z
- 実行時間: T分

### マージ済みブランチ
- feature/{branch-1}
- feature/{branch-2}

### 次のWave
Wave {N+1} を開始します...
```

#### Step 11.5: Post-Wave Code Review (Delegated to Review Coordinator)

After Wave N merges, run code review if not skipped:

```bash
if [ "${AAD_SKIP_REVIEW:-false}" = "true" ]; then
  echo "ℹ コードレビューをスキップしました (AAD_SKIP_REVIEW=true)"
  # → 次の Wave または Phase 4 へ進む
fi
```

If not skipped, **spawn review coordinator** (dedicated agent with fresh context):

```bash
DIFF=$(git diff ${WAVE_START_REF}..HEAD)
CHANGED_FILES=$(git diff --name-only ${WAVE_START_REF}..HEAD)
COMMITS=$(git log --oneline ${WAVE_START_REF}..HEAD)
```

```
Task(
  subagent_type: "general-purpose",
  name: "review-coordinator-wave-{N}",
  prompt: """
  You are the Code Review Coordinator for Wave {N}.

  **Project**: {projectDir}
  **Wave**: {N}
  **Changed Files**: {CHANGED_FILES}
  **Commits**: {COMMITS}
  **Diff**: {DIFF}

  ## YOUR MISSION

  Perform a PARALLEL code review using 3-5 specialized reviewer agents.
  You MUST NOT review the code yourself. You are a COORDINATOR, not a reviewer.

  ## EXECUTION STEPS

  1. Create review team:
     TeamCreate(team_name: "review-wave-{N}-{timestamp}")

  2. Classify changed files:
     - Backend: .py, .go, .rs, .java, .rb
     - Frontend: .ts, .tsx, .js, .jsx, .vue
     - Config: .yaml, .yml, .json, .toml, .env
     - Tests: *_test.*, *.test.*, tests/, __tests__/

  3. Spawn ALL reviewers in ONE message (minimum 3 Task calls):
     Task(name: "reviewer-bugs",    subagent_type: "general-purpose", prompt: "You are a bug-detector reviewer. Review this diff for bugs, logic errors, null pointer issues, off-by-one errors. Diff: {DIFF}. Files: {CHANGED_FILES}. Return findings as: severity (Critical/Warning/Info), file, line, description.")
     Task(name: "reviewer-quality", subagent_type: "general-purpose", prompt: "You are a code-quality reviewer. Review this diff for code quality: naming, DRY violations, complexity, error handling patterns. Diff: {DIFF}. Files: {CHANGED_FILES}. Return findings as: severity, file, line, description.")
     Task(name: "reviewer-tests",   subagent_type: "general-purpose", prompt: "You are a test-coverage reviewer. Review this diff for test coverage gaps, missing edge case tests, test quality issues. Diff: {DIFF}. Files: {CHANGED_FILES}. Return findings as: severity, file, line, description.")

     If backend/config files changed, also spawn:
     Task(name: "reviewer-security", subagent_type: "general-purpose", prompt: "You are a security reviewer. Review for SQL injection, XSS, auth issues, hardcoded secrets, CORS misconfig. Diff: {DIFF}. Files: {CHANGED_FILES}.")

     If backend files changed, also spawn:
     Task(name: "reviewer-perf", subagent_type: "general-purpose", prompt: "You are a performance reviewer. Review for N+1 queries, missing indexes, unnecessary allocations, blocking operations. Diff: {DIFF}. Files: {CHANGED_FILES}.")

  4. Wait for all reviewers to complete. Collect all findings.

  5. Validate findings:
     - Cross-check Critical findings with actual code (Grep)
     - Downgrade false positives
     - Deduplicate across reviewers

  6. TeamDelete()

  7. Return final review report:
     ## Wave {N} コードレビュー結果
     - Critical: N件
     - Warning: N件
     - Info: N件
     [detailed findings]

  8. If Critical issues found:
     Fix them directly (up to 3 rounds of fix → test → verify).
     Commit fixes: fix(review): {description}
  """
)
```

Wait for review-coordinator to complete. Display results.

### Phase 4: Final Completion

After all Waves complete:

1. Display final summary
2. Run tests (if test command available)
3. Display commit log
4. Suggest next steps

## Output Format (in Japanese)

```markdown
# Agent Team実行開始

## プランロード
✓ plan.json を読み込みました
✓ 全Wave数: 3
✓ 実行対象: 全Wave

## Wave 0: Bootstrap実行中
### タスク 1: コアモデル作成
✓ src/models/order.py を作成
✓ src/models/portfolio.py を作成
✓ テスト追加
✓ コミット完了

Wave 0 完了 (1タスク、2ファイル、2コミット)

## Wave 1: Parallel実行中
### チーム作成
✓ wave-1チームを作成

### Worktree作成
✓ agent-order: {path}/agent-order (feature/order)
✓ agent-portfolio: {path}/agent-portfolio (feature/portfolio)

### エージェント起動
✓ agent-order (sonnet) を起動
✓ agent-portfolio (opus) を起動

### 完了待機中...
[agent-orderからメッセージ] タスク完了 (3コミット)
[agent-portfolioからメッセージ] タスク完了 (4コミット)

### マージ実行
✓ feature/order をマージ
✓ feature/portfolio をマージ

### クリーンアップ
✓ Worktree削除完了
✓ エージェントシャットダウン完了

Wave 1 完了 (2エージェント、4ファイル、7コミット)

## 全Wave完了

### 最終サマリー
- 実行Wave数: 3
- 合計エージェント数: 5
- 実装ファイル数: 12
- 合計コミット数: 23
- 実行時間: 8分

### テスト実行
✓ 全テスト通過 (45 passed)

### 次のステップ
実装が完了しました。以下を確認してください:
1. テスト結果を確認
2. コミット履歴を確認: `git log --oneline`
3. 実装内容をレビュー

クリーンアップする場合: `/aad:cleanup`
```

## Important Constraints
- Never skip TDD cycle
- Respect merge order (dependencies)
- Handle conflicts gracefully
- Continue partial execution on agent failure (report at end)
- Update state.json after each Wave
- Clean up resources even if errors occur
</instructions>

## Tool Guidance
- **Bash** for git operations
- **Task** for spawning agents
- **TeamCreate** for team creation
- **TaskCreate/TaskUpdate/TaskList** for task management
- **SendMessage** for agent communication
- **TeamDelete** for cleanup
- **Read/Write** for state management
- **Edit** for state updates

## Safety & Fallback
- **No Plan**: If plan.json not found:
  ```
  エラー: 実装計画が見つかりません
  '/aad:plan' コマンドで計画を作成してください
  ```
- **Merge Conflict**: If conflict detected:
  ```
  ⚠ マージコンフリクトが発生しました
  以下のファイルを手動で解決してください:
  - {file1}
  - {file2}
  
  解決後、以下を実行:
  git add {files}
  git commit
  
  その後 '/aad:execute {wave}' で再開してください
  ```
- **Agent Failure**: If agent fails:
  ```
  ⚠ {agent-name} が失敗しました: {error}
  
  オプション:
  1. リトライ: '/aad:execute {wave}'
  2. スキップ: 手動で実装後、次Waveへ
  3. 中止: '/aad:cleanup'
  ```
- **Partial Completion**: Save state to allow resume
