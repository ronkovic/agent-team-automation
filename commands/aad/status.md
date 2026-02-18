---
name: aad:status
description: Show Agent Team execution status and progress
requires_approval: false
allowed-tools: Read, Glob, Bash, TaskList
output_language: japanese
---

# Agent Team Status Check

**IMPORTANT**: Always output responses to users in Japanese.

<background_information>
- **Mission**: Display Agent Team execution status and progress
- **Success Criteria**:
  - Read config files and display current state
  - Show Wave progress and agent status
  - Display Git worktree/branch state
  - Show remaining tasks
  - Calculate and display overall progress
</background_information>

<instructions>
## Core Task
Display current execution status and progress of Agent Team.

## Arguments
None (auto-detect from `.claude/aad/project-config.json` or current directory)

## Execution Steps

### 1. Read Config Files
- Read `.claude/aad/project-config.json`
- Read `.claude/aad/plan.json` (if exists)
- Read `.claude/aad/state.json` (if exists)
- Handle gracefully if files don't exist

### 2. Display Project Information
- Project directory
- Worktree directory
- Parent branch
- Initialization timestamp
- Current status

### 3. Display Wave Progress (if plan.json exists)
- Total Wave count
- Current Wave number
- Completed Waves list
- Pending Waves list

### 4. Display Agent Status (if state.json exists)
- Agent name
- Status (pending, in_progress, completed)
- Number of commits
- Assigned files
- Dependencies

### 5. Display Git State
- Run `git worktree list` and display results
- Run `git branch` and display feature/* branches
- Show merge status

### 6. Check Remaining Tasks (if team exists)
- Use `TaskList` tool
- Display task IDs, subjects, and statuses
- Show blocked/unblocked tasks

### 7. Display Progress Summary
- Overall progress percentage
- Completed task count
- In-progress task count
- Pending task count
- Estimated remaining work

## Output Format (in Japanese)

```markdown
# Agent Team実行状態

## プロジェクト情報
- プロジェクトディレクトリ: <path>
- Worktreeディレクトリ: <path>
- 親ブランチ: <branch>
- ステータス: <status>

## Wave進捗
- 全Wave数: X
- 現在のWave: Wave Y
- 完了: Wave 0, 1, 2
- 残り: Wave 3, 4

## エージェント状態
| エージェント | ステータス | コミット数 | ファイル |
|------------|----------|----------|---------|
| agent-xxx  | completed | 3 | order.py, test_order.py |
| agent-yyy  | in_progress | 1 | portfolio.py |

## Git状態
### Worktree
- <path>/agent-xxx (feature/xxx)
- <path>/agent-yyy (feature/yyy)

### ブランチ
- feature/xxx (merged)
- feature/yyy (active)

## タスク一覧
- #1 [completed] Task A
- #2 [in_progress] Task B (owner: agent-yyy)
- #3 [pending] Task C [blocked by #2]

## 進捗サマリー
- 全体進捗: 60% (3/5タスク完了)
- 完了: 3タスク
- 進行中: 1タスク
- 未着手: 1タスク
```

## Important Constraints
- Handle missing config files gracefully
- Display clear error messages if project not initialized
- Show informative messages if no execution in progress
- Format dates/times in readable format
</instructions>

## Tool Guidance
- Use **Read** to read JSON config files
- Use **Glob** to find config files if path not known
- Use **Bash** for:
  - `git worktree list`
  - `git branch --list 'feature/*'`
  - `git log` for commit history
- Use **TaskList** to get current task status (if team exists)

## Safety & Fallback
- **No Config File**: If `project-config.json` not found, display:
  ```
  エラー: プロジェクトが初期化されていません
  '/aad:init' コマンドでプロジェクトを初期化してください
  ```
- **No Execution**: If no state.json, display:
  ```
  情報: 実行が開始されていません
  '/aad:plan' でタスク計画を作成してください
  ```
- **JSON Parse Error**: If config file corrupted, display specific error
- **Git Command Error**: If git commands fail, show available information only
