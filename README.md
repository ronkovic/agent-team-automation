# Agent Team Automation Commands

Generalized reusable Claude Code custom commands + agents based on the proven Agent Team parallel implementation workflow from the trading-system project.

**Note**: All command prompts are in English for context efficiency, but **outputs to users are always in Japanese** (configured via `output_language: japanese` in front matter).

## 📁 Directory Structure

```
agent-team-automation/
├── CLAUDE.md                    # プロジェクトコンテキスト
├── agents/
│   ├── tdd-worker.md           # TDDワーカー（強化版）
│   ├── reviewer.md             # コードレビューエージェント
│   ├── merge-resolver.md       # マージ競合解決エージェント
│   ├── tester-red.md           # REDフェーズ専用エージェント
│   └── implementer.md          # GREENフェーズ専用エージェント
├── commands/aad/
│   ├── init.md                 # プロジェクト初期化
│   ├── plan.md                 # 計画生成（強化版）
│   ├── execute.md              # Wave実行（強化版）
│   ├── review.md               # コードレビュー（NEW）
│   ├── status.md               # 状態確認
│   ├── cleanup.md              # クリーンアップ（強化版）
│   └── run.md                  # エンドツーエンド（強化版）
└── scripts/
    ├── worktree.sh             # Git worktree管理（NEW）
    ├── tdd.sh                  # TDDパイプライン（NEW）
    ├── plan.sh                 # 計画ヘルパー（NEW）
    └── cleanup.sh              # クリーンアップ（NEW）
```

## 🚀 Installation

Copy files to `~/.claude/`:

```bash
cp -r agents/* ~/.claude/agents/
cp -r commands/* ~/.claude/commands/
```

Or create symlinks:

```bash
ln -s $(pwd)/agents/tdd-worker.md ~/.claude/agents/
mkdir -p ~/.claude/commands/aad
ln -s $(pwd)/commands/aad/*.md ~/.claude/commands/aad/
```

### Scripts

`scripts/` はプロジェクトリポジトリに配置するか、`PATH` に追加します:

```bash
# Option A: プロジェクトにコピー
cp -r scripts/ /path/to/your/project/scripts/

# Option B: PATH に追加（~/.zshrc / ~/.bashrc）
export PATH="/path/to/agent-team-automation/scripts:$PATH"

# Option C: 環境変数で明示指定
export AAD_SCRIPTS_DIR="/path/to/agent-team-automation/scripts"
```

スクリプトが見つからない場合はインライン Git コマンドに自動フォールバックします。

## 🛠 Available Commands

### `/aad:init` - Project Initialization

```bash
/aad:init [project-dir] [feature-name] [parent-branch]
```

- `project-dir` を省略するとカレントディレクトリを使用
- `project-dir` と見分けられない場合（パス形式でない文字列）は `feature-name` として扱う
- Verify or initialize Git repository
- Create parent branch (default: `aad/develop`)
- Create worktree parent directory (`<project-dir>-{feature-name}-wt/` or `<project-dir>-wt/` if no feature-name)
- Generate project config file (`.claude/aad/project-config.json`)

### `/aad:plan` - Plan Generation

```bash
/aad:plan <input-source>
```

**input-source**:
- File path: Requirements document
- Directory: Recursively read `.md`, `.yaml`, `.json`
- kiro spec: Auto-read `requirements.md` + `design.md` + `tasks.md`
- Text: Direct input

**Processing**:
- Scan existing codebase
- Wave division (dependency analysis)
- Model assignment (opus/sonnet/haiku)
- Generate `.claude/aad/plan.json`

### `/aad:execute` - Wave Execution

```bash
/aad:execute [wave-number]
```

- Wave 0: Leader executes shared code sequentially
- Wave 1+: Parallel agent execution → merge
- Auto-execute all Waves until completion

### `/aad:status` - Status Check

```bash
/aad:status
```

- Current Wave progress
- Agent status
- Git worktree/branch state
- Remaining tasks

### `/aad:review` - Code Review

```bash
/aad:review [base-ref] [--skip-fix]
```

- 3-5並列レビューエージェントによるコードレビュー
- カテゴリ: bug-detector, code-quality, test-coverage, performance, security
- Critical/Warning問題の自動修正ループ（最大3回）

### `/aad:cleanup` - Resource Cleanup

```bash
/aad:cleanup [--orphans]
```

- Remove worktrees
- Delete `feature/*` branches
- Archive state files
- `--orphans`: Clean up orphaned worktrees and branches

### `/aad:run` - End-to-End Execution

```bash
/aad:run [project-dir] <input-source> [parent-branch]
```

- `project-dir` を省略するとカレントディレクトリを使用
- Feature name is auto-derived from `<input-source>`.

Auto-execute: `init` → `plan` → `execute` → `cleanup`

## 📖 Workflow Examples

### Step-by-Step Execution

```bash
# プロジェクトディレクトリに移動して実行（project-dir 省略）
cd ~/my-project

# 1. Initialize
/aad:init                          # カレントディレクトリを使用
/aad:init auth-feature             # feature-name だけ指定

# 2. Generate plan (using kiro spec)
/aad:plan .kiro/specs/my-feature

# 3. Execute implementation
/aad:execute

# 4. Cleanup
/aad:cleanup
```

### End-to-End Execution

```bash
# カレントディレクトリで実行（project-dir 省略）
cd ~/my-project
/aad:run .kiro/specs/my-feature
/aad:run requirements.md

# 明示指定
/aad:run ~/my-project .kiro/specs/my-feature
```

## 🎯 Key Features

### Wave Division

Auto-divide tasks into parallel-executable Waves based on dependency analysis:

- **Wave 0**: Shared code (core models, interfaces)
- **Wave 1+**: Independent → dependent → integration order

### Model Assignment

Auto-select optimal model based on task complexity:

- **opus**: Financial logic, complex integration, precision-critical
- **sonnet**: Standard implementation (API integration, async design, tests)
- **haiku**: Boilerplate, config files, pattern-following

### Git Worktree Management

Each agent works in isolated worktree. The worktree directory name includes the feature name, allowing multiple `aad` runs for different features simultaneously:

```
my-project/                    # Parent repository
my-project-auth-wt/            # feature "auth" の worktree
  ├── agent-login/             # feature/login branch
  └── agent-register/          # feature/register branch

my-project-payment-wt/         # feature "payment" の worktree
  └── agent-checkout/          # feature/checkout branch
```

Feature name is auto-derived from the input source:
- `.kiro/specs/auth-feature/` → `auth-feature`
- `requirements.md` → `requirements`
- plain text → `unnamed`

### Shell Script Foundation

Robust shell script base for all Git operations:

```bash
# Framework detection
scripts/tdd.sh detect-framework .

# Run tests (auto-detected framework)
scripts/tdd.sh run-tests .

# Merge with spinlock (safe parallel merge)
scripts/tdd.sh merge-to-parent <worktree> <agent> <branch> <project>

# Worktree management
scripts/worktree.sh create-task <base> <name> <branch> <parent>
scripts/worktree.sh cleanup <base>
```

### Code Review System

Parallel review with auto-fix:

- 3-5 specialized reviewers run concurrently
- Categories: bug-detector, code-quality, test-coverage, performance, security
- Auto-fix loop for Critical/Warning issues (up to 3 rounds)
- Cross-pattern detection (systematic bugs)

### Spinlock-Based Parallel Merge

Safe merging when multiple agents finish simultaneously:

- Each agent merges itself using spinlock (`aad-merge.lock`)
- 120-second timeout
- Lock files auto-resolved with `--theirs`
- Source file conflicts handled by `merge-resolver` agent

### Draft PR Creation

Automatic draft PR creation after implementation:

```bash
/aad:run ~/my-project requirements.md
# Automatically creates draft PR with implementation summary
```

### TDD Cycle

All agents strictly apply TDD cycle:

1. **RED**: Write tests first (failing)
2. **GREEN**: Minimum implementation to pass tests
3. **REFACTOR**: Improve code quality
4. **REVIEW**: Verify all tests pass

## 📊 State Management

### `.claude/aad/project-config.json`

Project config (created at initialization):

```json
{
  "projectDir": "/absolute/path/to/project",
  "worktreeDir": "/absolute/path/to/project-auth-wt",
  "featureName": "auth",
  "parentBranch": "aad/develop",
  "createdAt": "2026-02-18T00:00:00.000Z",
  "status": "initialized"
}
```

### `.claude/aad/plan.json`

Implementation plan (created during plan phase):

```json
{
  "featureName": "auth",
  "waves": [
    {
      "id": 0,
      "type": "bootstrap",
      "tasks": [...]
    },
    {
      "id": 1,
      "type": "parallel",
      "agents": [
        {
          "name": "agent-order",
          "model": "sonnet",
          "branch": "feature/order",
          "tasks": [...],
          "files": [...],
          "dependsOn": []
        }
      ],
      "mergeOrder": [...]
    }
  ],
  "createdAt": "2026-02-18T00:00:00.000Z",
  "status": "pending_approval"
}
```

### `.claude/aad/state.json`

Execution state (updated during execution):

```json
{
  "currentWave": 2,
  "completedWaves": [0, 1],
  "agentStatus": {
    "agent-order": {
      "status": "completed",
      "commits": 3
    }
  },
  "mergeLog": [...],
  "updatedAt": "2026-02-18T00:00:00.000Z"
}
```

## ⚙️ CLI Options & Environment Variables

### `/aad:run` Options
| Option | Description |
|--------|-------------|
| `--dry-run` | Generate plan only, don't execute |
| `--keep-worktrees` | Skip worktree cleanup |
| `--workers N` | Max parallel workers |
| `--spec-only` | Generate requirements spec only |
| `--skip-review` | Skip code review step |

### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `AAD_WORKERS` | Number of parallel agents | auto |
| `AAD_SKIP_COMPLETED` | Skip completed Waves | false |
| `AAD_STRICT_TDD` | Enforce TDD cycle | false |
| `AAD_SCRIPTS_DIR` | Path to scripts/ directory | auto-detect |

## 🔍 Implementation Track Record

Proven in trading-system project:

- **14 agents × 4 waves** parallel implementation
- **60+ files** auto-generated
- **TDD cycle** for high-quality implementation
- **Git worktree management** for safe merging

## 📝 Commit Convention

Conventional Commits format:

```
<type>(<scope>): <description>

test(order): add tests for order validation
feat(order): implement order creation logic
refactor(order): extract validation into separate function
fix(portfolio): handle empty position list
```

## 🛡 Error Handling

- **Partial failure continuation**
- **Detailed error messages**
- **State file progress tracking**
- **Auto-cleanup of worktrees/branches**

## 🌐 Language Configuration

- **Command prompts**: English (for context efficiency)
- **User outputs**: Japanese (via `output_language: japanese`)
- **Code/commits**: English (standard practice)

## 📚 References

- Original design plan: Design document used to implement this toolset
- trading-system: Proven parallel implementation example
- kiro spec: Integration with Spec-Driven Development

## 🎓 License

This toolset was generalized from proven implementation in the trading-system project.
