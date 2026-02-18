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
1. Read `.claude/aad/plan.json`
2. Read `.claude/aad/state.json` (or create if not exists)
3. Determine Waves to execute (specific Wave or all pending)
4. Verify plan status is valid

### Phase 1.5: Detect Scripts Directory

Detect the location of shell scripts:
```bash
# Find scripts directory relative to .claude/aad/project-config.json
# or use environment variable if set
if [ -n "${AAD_SCRIPTS_DIR:-}" ]; then
  SCRIPTS_DIR="$AAD_SCRIPTS_DIR"
elif [ -f "$(git rev-parse --show-toplevel)/scripts/worktree.sh" ]; then
  SCRIPTS_DIR="$(git rev-parse --show-toplevel)/scripts"
else
  # Fallback: use inline git commands
  SCRIPTS_DIR=""
fi
```

### Phase 2: Execute Wave 0 (Bootstrap)

**Sequential execution by team-lead**:

1. Get Wave 0 tasks from plan.json
2. For each task in Wave 0:
   - Display task description
   - Implement shared code (core models, interfaces)
   - Run tests
   - Commit to parent branch directly
   - Update progress
3. Mark Wave 0 as completed in state.json
4. Display Wave 0 completion summary

**Wave 0 Commit Convention**:
```
feat(core): implement <description>
test(core): add tests for <description>
```

### Phase 3: Execute Wave 1+ (Parallel)

For each Wave N (N >= 1):

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

#### Step 4: Spawn Agents in Parallel
For each agent:
```
Task(
  subagent_type: "general-purpose",
  team_name: "wave-{N}",
  name: "{agent-name}",
  model: "{opus|sonnet|haiku}",  # from plan.json
  prompt: """
    You are {agent-name} working on Wave {N}.
    
    **Working Directory**: {worktree-path}
    **Branch**: feature/{branch-name}
    **Model**: {model}
    **Tasks**: {task-list}
    **Files**: {file-list}
    
    Follow TDD methodology (refer to tdd-worker agent definition):
    1. RED: Write tests first
    2. GREEN: Implement minimum code to pass
    3. REFACTOR: Improve code quality
    4. REVIEW: Verify all tests pass
    
    **Interface References**: {interface-files}
    **Dependencies**: {dependency-info}
    
    **Commit Convention**:
    - test({module}): add tests for {feature}
    - feat({module}): implement {feature}
    - refactor({module}): {description}
    
    **Completion**:
    - All tests pass
    - Code committed
    - TaskUpdate with status=completed
    
    Work autonomously. Report only when complete or blocked.
  """
)
```

Spawn all agents in parallel (single message with multiple Task calls).

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
git worktree remove {worktreeDir}/{agent-name}
git branch -d feature/{branch-name}  # only if fully merged
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

#### Step 10: Update State
Update state.json:
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

#### Step 11.5: Post-Wave Code Review (Optional)

After Wave N merges, run code review if not skipped:
```
if [ "${AAD_SKIP_REVIEW:-false}" != "true" ]; then
  # Invoke /aad:review for this Wave's changes
  # (See commands/aad/review.md for full implementation)
  echo "コードレビューを実行中..."
fi
```

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
