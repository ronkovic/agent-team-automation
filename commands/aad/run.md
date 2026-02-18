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
   - Wave 0: Bootstrap (shared code)
   - Wave 1+: Parallel groups
   - Optimize for parallelism

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

1. **Execute Wave 0** (team-lead sequential)
   - Implement shared code
   - Commit to parent branch
   - Run tests
   - Update state

2. **Execute Each Wave N** (N >= 1)
   - Create team
   - Create worktrees
   - Create tasks
   - Spawn agents in parallel
   - Monitor completion
   - Merge in order
   - Cleanup worktrees
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

### Phase 3.5: Code Review

After all Waves complete (unless --skip-review):
```
Invoke /aad:review logic with base-ref = initial branch before implementation
Display review results
If Critical issues found:
  "⚠ コードレビューでCritical問題が検出されました。修正しますか？ (y/N):"
  If yes: run auto-fix loop (up to 3 rounds)
```

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
