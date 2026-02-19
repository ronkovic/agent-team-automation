---
name: aad:run
description: End-to-end execution of Agent Team workflow (init → plan → execute → cleanup)
requires_approval: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, WebSearch, Task, TaskCreate, TaskUpdate, TaskList, TeamCreate, SendMessage, TeamDelete
output_language: japanese
---

# Agent Team Full Workflow

**IMPORTANT**: Always output responses to users in Japanese.

<background_information>
- **Mission**: Execute complete Agent Team workflow from initialization to cleanup
- **Success Criteria**:
  - Initialize project successfully
  - Generate valid implementation plan
  - Execute all Waves with parallel agents
  - Pass all tests
  - Cleanup resources
  - Deliver complete implementation
</background_information>

<instructions>
## Core Task
Execute full Agent Team workflow: init → plan → execute → cleanup.

## Arguments
- `$1`: `[project-dir]` - Target project directory (optional, default: current directory)
- `$2`: `<input-source>` - Requirements input (file/directory/kiro spec/text) (required if `$1` is project-dir)
- `$3`: `[parent-branch]` - Parent branch name (optional, default: `aad/develop`)

### Argument Auto-Detection

If `$1` does not look like a path (no `/`, `./`, `../` prefix and not an existing directory),
treat it as `input-source` and use the current working directory as `project-dir`:

| Invocation | project-dir | input-source |
|-----------|-------------|-------------|
| `/aad:run requirements.md` | `pwd` | `requirements.md` |
| `/aad:run .kiro/specs/auth-feature` | `pwd` | `.kiro/specs/auth-feature` |
| `/aad:run ./my-project requirements.md` | `./my-project` | `requirements.md` |
| `/aad:run "implement login feature"` | `pwd` | `"implement login feature"` |

## CLI Options
- `--dry-run`: Generate plan only, do not execute
- `--keep-worktrees`: Skip worktree cleanup after execution
- `--workers N`: Maximum parallel workers (default: auto, max CPU cores)
- `--spec-only`: Generate requirements.md only, stop before plan.json
- `--skip-review`: Skip code review step after each Wave

## Environment Variables
- `AAD_WORKERS`: Override --workers (number of parallel agents)
- `AAD_SKIP_COMPLETED`: Skip already-completed Waves (true/false)
- `AAD_STRICT_TDD`: Fail if TDD cycle is not followed (true/false)

## Workflow Phases

### Phase 1: Initialization

**Equivalent to `/aad:init`**:

1. **Parse Arguments with Auto-Detection**

   ```bash
   is_path() {
     [[ "$1" == /* ]] || [[ "$1" == ./* ]] || [[ "$1" == ../* ]] || [ -d "$1" ]
   }

   if [ -z "$1" ]; then
     echo "エラー: input-source を指定してください"
     exit 1
   elif is_path "$1" && [ -n "$2" ]; then
     # $1 is a path and $2 exists → $1=project-dir, $2=input-source
     PROJECT_DIR="$1"
     INPUT_SOURCE="$2"
     PARENT_BRANCH="${3:-aad/develop}"
   else
     # $1 is not a path (or $2 is absent) → $1=input-source, project-dir=cwd
     PROJECT_DIR="."
     INPUT_SOURCE="$1"
     PARENT_BRANCH="${2:-aad/develop}"
   fi
   ```

   **Parse CLI Options**:
   ```bash
   SKIP_REVIEW=false
   for arg in "$@"; do
     case "$arg" in
       --skip-review) SKIP_REVIEW=true ;;
       --dry-run) DRY_RUN=true ;;
       --keep-worktrees) KEEP_WORKTREES=true ;;
       --spec-only) SPEC_ONLY=true ;;
     esac
   done
   export AAD_SKIP_REVIEW="$SKIP_REVIEW"
   ```

   - Check resolved `project-dir` directory exists

2. **Feature Name Derivation**

   Derive `feature-name` from input-source (`$2`):
   1. If path is a directory: use basename (e.g., `.kiro/specs/auth-feature/` → `auth-feature`)
   2. If path is a file: use filename without extension (e.g., `requirements.md` → `requirements`)
   3. If plain text (not a path): use `unnamed`

   Sanitize: replace spaces and special characters with hyphens, convert to lowercase.

   ```bash
   INPUT_SOURCE="$2"
   if [ -d "$INPUT_SOURCE" ]; then
     FEATURE_NAME=$(basename "${INPUT_SOURCE%/}")
   elif [ -f "$INPUT_SOURCE" ]; then
     FEATURE_NAME=$(basename "$INPUT_SOURCE" | sed 's/\.[^.]*$//')
   else
     FEATURE_NAME="unnamed"
   fi
   # Sanitize: lowercase, replace non-alphanumeric (except -) with hyphen
   FEATURE_NAME=$(echo "$FEATURE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/-\+/-/g' | sed 's/^-\|-$//g')
   ```

3. **Initialize Git**
   - Check if `.git` exists
   - Run `git init` if needed
   - Display status

4. **Create Parent Branch**
   - Use `$3` or default `aad/develop`
   - Create branch if not exists

5. **Create Worktree Directory**
   - Create `{project-dir}-{feature-name}-wt/`
   - Handle existing directory

6. **Generate Config**
   - Create `.claude/aad/project-config.json`:
   ```json
   {
     "projectDir": "{abs-path}",
     "worktreeDir": "{abs-path}-{feature-name}-wt",
     "featureName": "{feature-name}",
     "parentBranch": "{branch}",
     "createdAt": "{ISO8601}",
     "status": "initialized"
   }
   ```

7. **Display Init Summary**
   ```markdown
   ## Phase 1: 初期化完了
   ✓ Feature名: {feature-name}
   ✓ Gitリポジトリ: {status}
   ✓ 親ブランチ: {branch}
   ✓ Worktreeディレクトリ: {path}
   ✓ 設定ファイル: .claude/aad/project-config.json
   ```

### Phase 2: Plan Generation

**Equivalent to `/aad:plan`**:

1. **Parse Input Source**
   - Determine type (file/directory/kiro spec/text)
   - Read and combine content
   - Extract requirements

2. **Scan Codebase**
   - Detect project structure
   - Identify language/framework
   - List existing files

3. **Analyze Dependencies**
   - Parse requirements
   - Identify shared code
   - Determine task dependencies

4. **Generate Wave Division**
   - Wave 0: Bootstrap (shared code, core models, interfaces)
   - Wave 1+: Parallel groups
   - Optimize for parallelism
   - **Import dependency rule**: If module A does `from B import ...` or `import B`, then A MUST be in a later Wave than B. Example: `cli.py` imports `commands.py` → cli must be in a later Wave than commands.

5. **Assign Models**
   - opus: Complex/critical tasks
   - sonnet: Standard implementation
   - haiku: Boilerplate/simple tasks

6. **Create plan.json**
   - Full Wave structure
   - Agent assignments
   - Merge order

7. **Display Plan Summary**
   ```markdown
   ## Phase 2: 計画生成完了
   
   ### 概要
   - 全Wave数: {count}
   - エージェント数: {count}
   - 対象ファイル数: {count}
   
   ### Wave構成
   {detailed wave breakdown}
   ```

8. **Request User Approval**
   ```
   この計画で実行を続けますか？
   続行する場合は 'y' を入力してください: 
   ```

   - Wait for user input
   - If not 'y', exit gracefully
   - If 'y', proceed to Phase 3

### Phase 3: Execution

**Equivalent to `/aad:execute`**:

#### Save Review Baseline
Before any Wave execution, save the current commit hash as the review baseline:
```bash
INITIAL_BRANCH_REF=$(git rev-parse HEAD)
```

#### Step 0: Install Dependencies

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

1. **Execute Wave 0** (team-lead sequential)
   **IMPORTANT: Wave 0 does NOT use a worktree or feature branch.**
   Work directly on the parent branch ({parentBranch}) in the main project directory ({projectDir}).
   **Do NOT create a worktree. Do NOT create a feature branch. Do NOT spawn agents.**

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

   Follow TDD cycle with **separate commits per phase**:
   - **RED**: Write failing tests first → **MUST commit NOW** (do not combine with GREEN):
     `test(core): add tests for <description>`
   - **GREEN**: Write minimum implementation to pass tests → **MUST commit NOW** (do not combine with RED):
     `feat(core): implement <description>`
   - **REFACTOR**: Improve code quality, verify tests still pass → commit if changed:
     `refactor(core): <description>`
   - Update state

2. **Execute Each Wave N** (N >= 1)
   - Create team
   - Create worktrees using: `${SCRIPTS_DIR}/worktree.sh create-task ...`
   - Create tasks
   - Spawn agents in parallel (**ALL agents in a SINGLE message**)
     - Each agent prompt MUST include: Working Directory, Branch, Scripts Directory, TDD instructions
     - **Cross-stack contract**: If a Wave contains both frontend and backend agents, include the shared API contract (HTTP methods, request/response formats, status codes) in BOTH agent prompts
   - Monitor completion (agents self-merge via `${SCRIPTS_DIR}/tdd.sh merge-to-parent`)
   - **Do NOT merge manually** — agents handle their own merge with spinlock
   - Cleanup worktrees after all agents complete
   - **Reinstall dependencies** in {projectDir} after merge (merges may introduce new package.json / go.mod / pyproject.toml)
   - Shutdown agents
   - Update state
   - Display Wave summary

3. **Display Execution Progress**
   ```markdown
   ## Phase 3: 実装実行中
   
   ### Wave 0: Bootstrap
   ✓ コアモデル実装完了
   
   ### Wave 1: Parallel (2エージェント)
   ✓ agent-order 完了 (3コミット)
   ✓ agent-portfolio 完了 (4コミット)
   ✓ マージ完了
   
   ### Wave 2: Parallel (1エージェント)
   ✓ agent-integration 完了 (2コミット)
   ✓ マージ完了
   ```

4. **Run Tests** (if available)
   **Before running tests, ensure dependencies are installed** (defensive check):
   ```bash
   cd {projectDir}
   # npm
   if [ -f "frontend/package.json" ] && [ ! -d "frontend/node_modules" ]; then
     echo "⚠ frontend/node_modules が未インストール。npm install を実行..."
     (cd frontend && npm install)
   elif [ -f "package.json" ] && [ ! -d "node_modules" ]; then
     echo "⚠ node_modules が未インストール。npm install を実行..."
     npm install
   fi
   # go
   if [ -f "backend/go.mod" ] && command -v go >/dev/null 2>&1; then
     (cd backend && go mod download)
   elif [ -f "go.mod" ] && command -v go >/dev/null 2>&1; then
     go mod download
   fi
   ```
   - Detect test command (npm test, pytest, go test, etc.)
   - Run all tests
   - Display results

5. **Display Execution Summary**
   ```markdown
   ## Phase 3: 実装完了
   
   ### 統計
   - 実行Wave数: {count}
   - 合計エージェント数: {count}
   - 実装ファイル数: {count}
   - 合計コミット数: {count}
   - テスト: {passed} passed, {failed} failed
   ```

### Phase 3.5: Code Review (Delegated to Review Coordinator)

After all Waves complete, perform code review (unless `--skip-review` specified):

**Skip check**:
```bash
if [ "$SKIP_REVIEW" = "true" ]; then
  echo "ℹ コードレビューをスキップしました (--skip-review)"
  # → Phase 4 へ進む
fi
```

**Spawn review coordinator** (dedicated agent with fresh context):

```bash
cd {projectDir}
DIFF=$(git diff ${INITIAL_BRANCH_REF}..HEAD)
CHANGED_FILES=$(git diff --name-only ${INITIAL_BRANCH_REF}..HEAD)
COMMITS=$(git log --oneline ${INITIAL_BRANCH_REF}..HEAD)
```

```
Task(
  subagent_type: "general-purpose",
  name: "review-coordinator",
  prompt: """
  You are the Code Review Coordinator.

  **Project**: {projectDir}
  **Changed Files**: {CHANGED_FILES}
  **Commits**: {COMMITS}
  **Diff**: {DIFF}

  ## YOUR MISSION

  Perform a PARALLEL code review using 3-5 specialized reviewer agents.
  You MUST NOT review the code yourself. You are a COORDINATOR, not a reviewer.

  ## EXECUTION STEPS

  1. Create review team:
     TeamCreate(team_name: "review-{timestamp}")

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
     ## コードレビュー結果
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

### Phase 4: Cleanup

**Equivalent to `/aad:cleanup`**:

1. **Remove Worktrees**
   - List all worktrees
   - Remove each worktree
   - Handle errors gracefully

2. **Delete Branches**
   - List feature/* branches
   - Delete merged branches
   - Keep unmerged (warn)

3. **Archive State Files**
   - Create archive directory
   - Move config/plan/state to archive
   - Display archive location

4. **Remove Worktree Directory**
   - Delete `{project-dir}-{feature-name}-wt/` (read path from project-config.json `worktreeDir`)

5. **Display Cleanup Summary**
   ```markdown
   ## Phase 4: クリーンアップ完了
   ✓ Worktree削除: {count}個
   ✓ ブランチ削除: {count}個
   ✓ アーカイブ: .claude/aad/archive/{timestamp}/
   ```

### Phase 4.5: Create Draft Pull Request

If gh command available and on git repository with remote:
```bash
# Check if gh is available
if command -v gh &> /dev/null; then
  # Get implementation summary
  WAVE_COUNT=$(cat .claude/aad/state.json | jq '.completedWaves | length')

  gh pr create --draft \
    --title "feat: {implementation title from plan}" \
    --body "$(cat <<'EOF'
## 実装サマリー

### Agent Team実装
- Wave数: {WAVE_COUNT}
- エージェント数: {AGENT_COUNT}
- 実装ファイル数: {FILE_COUNT}

### 実装内容
{summary from plan.json tasks}

### テスト
{test results}

### レビュー
{review results if /aad:review was run}

---
*Generated by /aad:run*
EOF
)"

  echo "✓ Draft PRを作成しました: {PR_URL}"
fi
```

### Phase 5: Final Report

```markdown
# Agent Team実行完了

## 全体サマリー

### フェーズ実行結果
✓ Phase 1: 初期化
✓ Phase 2: 計画生成
✓ Phase 3: 実装実行
✓ Phase 4: クリーンアップ

### 実装統計
- Wave数: {count}
- エージェント数: {count}
- 実装ファイル数: {count}
- コミット数: {count}
- テスト: {passed} passed
- 実行時間: {duration}分

### 最終状態
- ブランチ: {parent-branch}
- 最新コミット: {hash} {message}
- アーカイブ: .claude/aad/archive/{timestamp}/

### 次のステップ
実装が完了しました。以下を確認してください:

1. **コード確認**
   ```bash
   git log --oneline
   git diff {original-branch}..{parent-branch}
   ```

2. **テスト確認**
   ```bash
   {test-command}
   ```

3. **レビュー**
   - 実装内容を確認
   - テストカバレッジを確認
   - ドキュメント更新

4. **デプロイ準備**
   - 本番ブランチへのマージ準備
   - CI/CDパイプライン確認
```

## Error Handling

### Phase 1 Error
If initialization fails:
- Display specific error
- Exit without cleanup
- Guide user to fix issue

### Phase 2 Error
If plan generation fails:
- Display specific error
- Keep initialization (don't cleanup)
- Allow retry with `/aad:plan`

### Phase 3 Error
If execution fails:
- Display Wave and agent where failed
- Save state for resume
- Options:
  1. Retry: `/aad:execute {wave}`
  2. Manual fix + continue
  3. Cleanup: `/aad:cleanup`

### Phase 4 Error
If cleanup fails:
- Display partial cleanup status
- Guide manual cleanup steps
- List remaining resources

## Recovery Options

For each error, provide:
```markdown
⚠ エラーが発生しました: {error}

### 状況
{detailed status}

### 復旧オプション
1. **リトライ**: 同じフェーズを再実行
2. **手動修正**: エラーを手動で修正後、続行
3. **中止**: 現在の状態で中止

選択してください (1/2/3):
```

## Important Constraints
- Always require user approval before Phase 3
- Save state at each phase completion
- Enable phase-level resume on error
- Display progress throughout execution
- Provide clear error messages
- Suggest recovery options
</instructions>

## Tool Guidance
- Use all tools from init, plan, execute, cleanup commands
- Coordinate tool usage across phases
- Handle state transitions carefully
- Maintain consistent error handling

## Output Format (in Japanese)

Use clear phase headers:
```markdown
# Agent Team完全実行

## Phase 1: 初期化
{init output}

## Phase 2: 計画生成
{plan output}

### 承認待ち
この計画で実行を続けますか？ (y/N):

## Phase 3: 実装実行
{execute output}

## Phase 4: クリーンアップ
{cleanup output}

## 完了サマリー
{final report}
```

## Safety & Fallback
- **Missing Arguments**: If no arguments at all, display usage and exit
  ```
  使用方法: /aad:run [project-dir] <input-source> [parent-branch]
  例: /aad:run requirements.md                          # カレントディレクトリを使用
  例: /aad:run .kiro/specs/auth-feature                 # feature-name は "auth-feature" に自動派生
  例: /aad:run ./my-project requirements.md             # 明示指定
  ```
- **User Rejection**: If user doesn't approve plan:
  ```
  実行をキャンセルしました。
  プランを修正する場合は '/aad:plan' を再実行してください。
  ```
- **Partial Completion**: Save progress at each phase
- **Resume Capability**: Allow resuming from last completed phase
