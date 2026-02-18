---
name: aad:review
description: Parallel code review with auto-fix loop for critical/warning issues
requires_approval: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TeamCreate, SendMessage, TeamDelete
output_language: japanese
---

# Parallel Code Review

**IMPORTANT**: Always output responses to users in Japanese.

<background_information>
- **Mission**: Run parallel code review and auto-fix critical/warning issues
- **Success Criteria**:
  - Collect git diff and changed files
  - Run 3-5 parallel review agents by category
  - Validate findings
  - Auto-fix Critical/Warning issues (up to 3 rounds)
  - Generate final review report
</background_information>

<instructions>
## Core Task
Perform parallel code review and auto-fix loop.

## Arguments
- `$1`: `[base-ref]` - Base git ref for diff (default: parent branch or HEAD~1)
- `$2`: `[--skip-fix]` - Skip auto-fix loop (optional)

## Execution Steps

### Step 1: Collect Context

```bash
# Get changed files
BASE_REF="${1:-HEAD~1}"
git diff --name-only ${BASE_REF}..HEAD

# Get diff
git diff ${BASE_REF}..HEAD

# Get recent commits
git log --oneline ${BASE_REF}..HEAD
```

### Step 2: Classify Files by Category

Classify changed files:
- **Backend**: `.py`, `.go`, `.rs`, `.java`, `.rb`
- **Frontend**: `.ts`, `.tsx`, `.js`, `.jsx`, `.vue`
- **Config**: `.yaml`, `.yml`, `.json`, `.toml`, `.env`
- **Tests**: `*_test.*`, `*.test.*`, `tests/`, `__tests__/`
- **Scripts**: `.sh`, `Makefile`

### Step 3: Spawn Parallel Review Agents

Spawn 3-5 review agents based on changed file types:

```
TeamCreate(team_name: "review-wave-{timestamp}")

Spawn in parallel:
- Task(name: "reviewer-bugs", prompt: "Category: bug-detector. Diff: {diff}. Files: {files}. Use reviewer agent definition.")
- Task(name: "reviewer-quality", prompt: "Category: code-quality. Diff: {diff}. Files: {files}. Use reviewer agent definition.")
- Task(name: "reviewer-tests", prompt: "Category: test-coverage. Diff: {diff}. Files: {files}. Use reviewer agent definition.")
- Task(name: "reviewer-security", prompt: "Category: security. Diff: {diff}. Files: {files}. Use reviewer agent definition.") [if Backend/Config files changed]
- Task(name: "reviewer-perf", prompt: "Category: performance. Diff: {diff}. Files: {files}. Use reviewer agent definition.") [if Backend files changed]
```

Wait for all reviewers to complete.

### Step 4: Validate Findings

Cross-validate Critical findings:
- For each Critical finding: search the pattern across all changed files with Grep
- Downgrade to Warning if pattern only found in one place (may be intentional)
- Upgrade Info to Warning if same issue found in 3+ files (systematic problem)

### Step 5: Cross-Pattern Check

For each Critical finding pattern, search all changed files:
```bash
grep -n "{pattern}" {changed_files}
```

Report systemic issues (same bug in multiple files).

### Step 6: Generate Review Report

```markdown
## コードレビュー結果

### サマリー
- レビュー対象ファイル: X
- Critical: X件
- Warning: X件
- Info: X件

### Critical（要修正）
{findings from all reviewers, deduplicated}

### Warning（推奨修正）
{findings}

### Info（参考情報）
{findings}

### カテゴリ別結果
- bug-detector: Critical X, Warning Y
- code-quality: Critical X, Warning Y
- test-coverage: Critical X, Warning Y
- security: Critical X, Warning Y
- performance: Critical X, Warning Y
```

### Step 7: Auto-Fix Loop

If Critical or Warning issues found AND `--skip-fix` not specified:

```
MAX_ROUNDS=3
for round in 1..MAX_ROUNDS:
  if no Critical or Warning issues: break

  # Spawn parallel fixers by file category
  for each file with Critical/Warning issues:
    Task(
      name: "fixer-{file}",
      prompt: "Fix these issues in {file}: {issues}.
               Run tests after fixing: ${SCRIPTS_DIR}/tdd.sh run-tests
               If tests fail, revert and report."
    )

  Wait for all fixers to complete
  Run tests
  Re-run review (Steps 3-6)

  Display round result:
  "修正ラウンド {round}: Critical {before} → {after}, Warning {before} → {after}"

if still Critical issues after MAX_ROUNDS:
  "⚠ 3ラウンド後もCritical問題が残っています。手動修正が必要です。"
```

### Step 8: Final Report

```markdown
## 最終レビュー結果

### 修正サマリー
- 修正ラウンド数: X / 3
- 修正したファイル: X
- 残存Critical: X件
- 残存Warning: X件

### 修正前後の比較
{before/after issue counts per category}

### 残存する問題
{list of unfixed issues with locations}
```

## Output Format (in Japanese)

Use clear section headers and progress indicators.

## Safety & Fallback
- **No Changes**: If no diff found: "レビュー対象の変更が見つかりません"
- **Test Failure After Fix**: Revert the fix and mark issue as "自動修正失敗"
- **All Fixed**: "✓ 全てのCritical/Warning問題が修正されました"
</instructions>
