---
name: aad:cleanup
description: Cleanup all Agent Team resources (worktrees, branches, state files)
requires_approval: true
allowed-tools: Bash, Read, Glob
output_language: japanese
---

# Agent Team Resource Cleanup

**IMPORTANT**: Always output responses to users in Japanese.

<background_information>
- **Mission**: Safely cleanup all Agent Team resources
- **Success Criteria**:
  - Remove all worktrees
  - Delete feature/* branches
  - Archive state files
  - Preserve important data
  - Warn about uncommitted changes
</background_information>

<instructions>
## Core Task
Cleanup all Agent Team resources (worktrees, branches, state files).

## Arguments
- `--orphans`: Clean up orphaned worktrees and branches (in addition to normal cleanup)

## Execution Steps

### 1. Read Config
- Read `.claude/aad/project-config.json`
- Get `worktreeDir` path
- Verify project directory

### 2. List Cleanup Targets
- Run `git worktree list` to enumerate worktrees under `worktreeDir`
- List all `feature/*` branches
- List state files in `.claude/aad/`
- Check for uncommitted changes in worktrees

### 3. Show Confirmation Prompt
- Display all targets to be deleted
- Warn if uncommitted changes found
- Ask for user confirmation (default: No)
- Require explicit 'y' input to proceed

### 4. Remove Worktrees
- For each worktree:
  - Check for uncommitted changes
  - Use script if available:
    ```bash
    if [ -n "${SCRIPTS_DIR:-}" ]; then
      ${SCRIPTS_DIR}/worktree.sh cleanup {worktreeDir}
    else
      # Inline fallback
      git worktree remove <path>
      git worktree remove --force <path>
    fi
    ```
  - Display progress
- Continue on individual errors (don't stop entire process)

### 5. Delete Branches
- For each `feature/*` branch:
  - Check if already merged
  - Run `git branch -D feature/<name>`
  - Display progress
- Continue on individual errors

### 6. Archive State Files
- Create `.claude/aad/archive/<timestamp>/` directory
- Move `project-config.json`, `plan.json`, `state.json` to archive
- Display archive location

### 7. Remove Worktree Directory
- Remove `<worktreeDir>` directory
- Handle if directory not empty (show contents)

### 9. Orphan Cleanup (if --orphans specified)

If `--orphans` flag provided:
```bash
if [ -n "${SCRIPTS_DIR:-}" ]; then
  ${SCRIPTS_DIR}/cleanup.sh orphans {projectDir}
else
  # Inline fallback
  git worktree prune
  git branch --merged | grep "feature/" | xargs git branch -d 2>/dev/null || true
fi
```

Display cleaned orphans.

### 8. Display Completion Summary
- Number of deleted worktrees
- Number of deleted branches
- Archive location
- Any errors encountered

## Confirmation Prompt Format (in Japanese)

```
以下のリソースを削除します:

Worktrees:
- /path/to/project-wt/agent-xxx (feature/xxx)
- /path/to/project-wt/agent-yyy (feature/yyy)

ブランチ:
- feature/xxx
- feature/yyy

状態ファイル (アーカイブされます):
- .claude/aad/project-config.json
- .claude/aad/plan.json
- .claude/aad/state.json

⚠ 警告: 以下のworktreeに未コミット変更があります:
- agent-xxx: 2 modified files

削除を実行しますか? (y/N):
```

## Output Format (in Japanese)

```markdown
# Agent Teamリソースクリーンアップ

## 削除対象の確認
<list targets>

## 実行中
### Worktree削除
✓ /path/to/agent-xxx を削除しました
✓ /path/to/agent-yyy を削除しました

### ブランチ削除
✓ feature/xxx を削除しました
✓ feature/yyy を削除しました

### 状態ファイルをアーカイブ
✓ .claude/aad/archive/2026-02-18T01-30-00/ に移動しました

### Worktreeディレクトリ削除
✓ /path/to/project-wt を削除しました

## クリーンアップ完了
- 削除したworktree: 2個
- 削除したブランチ: 2個
- アーカイブ場所: .claude/aad/archive/2026-02-18T01-30-00/
```

## Important Constraints
- **requires_approval: true** (destructive operation)
- Warn about uncommitted changes before deletion
- Continue partial cleanup on errors
- Never delete parent branch
- Preserve archived state files
- Handle "worktree locked" errors gracefully
</instructions>

## Tool Guidance
- Use **Bash** for:
  - `git worktree list`
  - `git worktree remove [--force] <path>`
  - `git branch -D <name>`
  - `git status --short` (check uncommitted changes)
  - `rm -rf <directory>`
  - `mkdir -p <archive-path>`
  - `mv <files> <archive-path>`
- Use **Read** to read config files
- Use **Glob** to find state files

## Safety & Fallback
- **No Config**: If config not found, display:
  ```
  エラー: プロジェクト設定が見つかりません
  クリーンアップ対象を特定できません
  ```
- **User Cancellation**: If user inputs anything except 'y':
  ```
  クリーンアップをキャンセルしました
  ```
- **Uncommitted Changes**: Warn but allow with --force option
- **Locked Worktree**: If worktree locked, explain and suggest manual removal
- **Partial Failure**: Continue cleanup and report errors at end
