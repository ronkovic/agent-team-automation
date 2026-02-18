---
name: aad:init
description: Initialize project for Agent Team parallel implementation
requires_approval: false
allowed-tools: Bash, Read, Write, Glob
argument-hint: <project-dir> [feature-name] [parent-branch]
output_language: japanese
---

# Team Project Initialization

**IMPORTANT**: Always output responses to users in Japanese.

<background_information>
- **Mission**: Initialize project for Agent Team parallel implementation
- **Success Criteria**:
  - Verify or initialize Git repository
  - Create parent branch
  - Create worktree parent directory
  - Generate project config file
  - Provide clear guidance for next steps
</background_information>

<instructions>
## Core Task
Initialize specified project directory for Agent Team parallel implementation.

## Arguments
- `$1`: `[project-dir]` - Target project directory (optional, default: current directory)
- `$2`: `[feature-name]` - Feature name (optional, auto-derived from input source)
- `$3`: `[parent-branch]` - Parent branch name (default: `aad/develop`)

### Argument Auto-Detection

If `$1` does not look like a path (no `/`, `./`, `../` prefix and not an existing directory),
treat it as `feature-name` and use the current working directory as `project-dir`:

| Invocation | project-dir | feature-name | parent-branch |
|-----------|-------------|-------------|--------------|
| `/aad:init` | `pwd` | — | `aad/develop` |
| `/aad:init auth-feature` | `pwd` | `auth-feature` | `aad/develop` |
| `/aad:init ./my-project` | `./my-project` | — | `aad/develop` |
| `/aad:init ./my-project auth-feature` | `./my-project` | `auth-feature` | `aad/develop` |

## Execution Steps

### 1. Parse Arguments
- If `$1` is empty → `project-dir` = current directory, no feature-name
- If `$1` starts with `/`, `./`, `../`, or is an existing directory → `project-dir` = `$1`, `feature-name` = `$2`, `parent-branch` = `$3`
- Otherwise → `project-dir` = current directory, `feature-name` = `$1`, `parent-branch` = `$2`

### 2. Check Directory Existence
- Check if resolved `project-dir` directory exists
- Display error message and exit if not exists
- Convert to absolute path for subsequent processing

### 3. Check/Initialize Git State
- Check if `$1/.git` exists
- If not exists:
  - Run `git init`
  - Display initialization completion message
- If exists:
  - Check and display current branch
  - Notify recognized as Git repository

### 4. Set/Create Parent Branch
- Use `aad/develop` as default if `$3` not specified
- Check if specified parent branch already exists
- If not exists:
  - Create parent branch
  - Display creation completion message
- If exists:
  - Notify using existing branch
  - Explicitly state won't overwrite

### 5. Create Worktree Parent Directory
- If `$2` (feature-name) is specified, generate path for `<project-dir>-{feature-name}-wt/` directory
- Otherwise, generate path for `<project-dir>-wt/` directory
- Check if directory already exists
- If not exists:
  - Create directory
  - Display creation completion message
- If exists:
  - Warn existing directory found
  - Use existing directory as is

### 6. Generate Config File
- Create `$1/.claude/aad/` directory if not exists
- Create `$1/.claude/aad/project-config.json` with format:
```json
{
  "projectDir": "<absolute-path>",
  "worktreeDir": "<absolute-path>-{feature-name}-wt",
  "featureName": "<feature-name>",
  "parentBranch": "<parent-branch-name>",
  "createdAt": "<ISO8601-timestamp>",
  "status": "initialized"
}
```
Note: `featureName` and the `{feature-name}` suffix in `worktreeDir` are omitted when `$2` is not specified (worktreeDir becomes `<absolute-path>-wt`).
- Display config file creation completion message

### 7. Completion Notification
- Notify initialization completed successfully
- Display list of generated files and directories
- Guide to use `/aad:plan` command as next step

## Important Constraints
- Don't overwrite existing files or directories
- Display clear error messages when errors occur
- Implement all operations with idempotency
- Use absolute paths to avoid path-related issues
</instructions>

## Tool Guidance
- Use **Bash** for:
  - Directory existence check (`[ -d "$dir" ]`)
  - Git repository check (`[ -d "$dir/.git" ]`)
  - Git initialization (`git init`)
  - Branch existence check (`git branch --list`)
  - Branch creation (`git branch`)
  - Directory creation (`mkdir -p`)
  - Get absolute path (`cd "$dir" && pwd`)
  - Generate ISO8601 timestamp (`date -u +"%Y-%m-%dT%H:%M:%SZ"`)
- Use **Read** to check existing config files
- Use **Write** to create `project-config.json`
- Use **Glob** to check files under `.claude/aad/`

## Output Description
Provide output with following structure (in Japanese):

1. **Initialization Start**: Display project directory and parent branch name
2. **Execution Status of Each Step**:
   - Git status (initialized or existing repository)
   - Parent branch (created or existing)
   - Worktree directory (created or existing)
   - Config file creation status
3. **Created Files/Directories**: Bulleted list
4. **Next Steps**: Display `/aad:plan` command usage in code block
5. **Notes**: Notify project initialized and ready for next work

**Format Requirements**:
- Output in Markdown format
- Enclose commands in code blocks
- Use concise and clear Japanese
- Clearly display result of each step

## Safety & Fallback
- **No Arguments**: Use current directory as project-dir
  ```
  # カレントディレクトリで初期化
  /aad:init
  /aad:init auth-feature              # feature-name のみ指定
  /aad:init ./my-project auth-feature # 全て明示指定
  ```
- **Directory Not Found**: If specified project directory doesn't exist, display error
  ```
  エラー: プロジェクトディレクトリが存在しません: <project-dir>
  ディレクトリを作成してから再実行してください。
  ```
- **Git Command Failure**: If Git commands fail, display specific error details
- **Write Permission Error**: If file/directory creation fails, guide to check permissions
- **Existing Config Conflict**: If `project-config.json` exists, warn without overwriting and preserve existing config

## Implementation Example

```bash
#!/bin/bash
set -e

# Parse arguments with auto-detection
is_path() {
  [[ "$1" == /* ]] || [[ "$1" == ./* ]] || [[ "$1" == ../* ]] || [ -d "$1" ]
}

if [ -z "$1" ]; then
  # No args: use current directory
  PROJECT_DIR="."
  FEATURE_NAME=""
  PARENT_BRANCH="aad/develop"
elif is_path "$1"; then
  # $1 is a path
  PROJECT_DIR="$1"
  FEATURE_NAME="${2:-}"
  PARENT_BRANCH="${3:-aad/develop}"
else
  # $1 is not a path: treat as feature-name, use current directory
  PROJECT_DIR="."
  FEATURE_NAME="$1"
  PARENT_BRANCH="${2:-aad/develop}"
fi

# Check directory existence
if [ ! -d "$PROJECT_DIR" ]; then
  echo "エラー: プロジェクトディレクトリが存在しません: $PROJECT_DIR"
  exit 1
fi

# Get absolute path
ABS_PROJECT_DIR=$(cd "$PROJECT_DIR" && pwd)
if [ -n "$FEATURE_NAME" ]; then
  WORKTREE_DIR="${ABS_PROJECT_DIR}-${FEATURE_NAME}-wt"
else
  WORKTREE_DIR="${ABS_PROJECT_DIR}-wt"
fi

echo "## プロジェクト初期化開始"
echo "- プロジェクトディレクトリ: $ABS_PROJECT_DIR"
echo "- 親ブランチ: $PARENT_BRANCH"
echo ""

# Initialize or check Git
cd "$ABS_PROJECT_DIR"
if [ ! -d ".git" ]; then
  echo "### Git リポジトリを初期化"
  git init
  echo "✓ Git リポジトリを初期化しました"
else
  echo "### Git リポジトリ確認"
  CURRENT_BRANCH=$(git branch --show-current)
  echo "✓ 既存の Git リポジトリ (現在のブランチ: $CURRENT_BRANCH)"
fi
echo ""

# Create parent branch
echo "### 親ブランチ設定"
if git show-ref --verify --quiet "refs/heads/$PARENT_BRANCH"; then
  echo "✓ 親ブランチ '$PARENT_BRANCH' は既に存在します"
else
  git branch "$PARENT_BRANCH"
  echo "✓ 親ブランチ '$PARENT_BRANCH' を作成しました"
fi
echo ""

# Create worktree directory
echo "### Worktree ディレクトリ作成"
if [ -d "$WORKTREE_DIR" ]; then
  echo "⚠ Worktree ディレクトリは既に存在します: $WORKTREE_DIR"
else
  mkdir -p "$WORKTREE_DIR"
  echo "✓ Worktree ディレクトリを作成しました: $WORKTREE_DIR"
fi
echo ""

# Create config file
echo "### 設定ファイル生成"
CONFIG_DIR="$ABS_PROJECT_DIR/.claude/aad"
CONFIG_FILE="$CONFIG_DIR/project-config.json"

mkdir -p "$CONFIG_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ -n "$FEATURE_NAME" ]; then
  cat > "$CONFIG_FILE" <<EOF
{
  "projectDir": "$ABS_PROJECT_DIR",
  "worktreeDir": "$WORKTREE_DIR",
  "featureName": "$FEATURE_NAME",
  "parentBranch": "$PARENT_BRANCH",
  "createdAt": "$TIMESTAMP",
  "status": "initialized"
}
EOF
else
  cat > "$CONFIG_FILE" <<EOF
{
  "projectDir": "$ABS_PROJECT_DIR",
  "worktreeDir": "$WORKTREE_DIR",
  "parentBranch": "$PARENT_BRANCH",
  "createdAt": "$TIMESTAMP",
  "status": "initialized"
}
EOF
fi

echo "✓ 設定ファイルを作成しました: $CONFIG_FILE"
echo ""

# Completion notification
echo "## 初期化完了"
echo ""
echo "作成されたファイル・ディレクトリ:"
echo "- $CONFIG_FILE"
echo "- $WORKTREE_DIR/"
echo "- Git ブランチ: $PARENT_BRANCH"
echo ""
echo "次のステップ:"
echo "\`\`\`"
echo "/aad:plan"
echo "\`\`\`"
echo ""
echo "プロジェクトがエージェントチーム並列実装用に初期化されました。"
echo "次は \`/aad:plan\` コマンドでタスク計画を作成してください。"
```
