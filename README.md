# Agent Team Automation Commands

Generalized reusable Claude Code custom commands + agents based on the proven Agent Team parallel implementation workflow from the trading-system project.

**Note**: All command prompts are in English for context efficiency, but **outputs to users are always in Japanese** (configured via `output_language: japanese` in front matter).

## 📁 Directory Structure

```
agent-team-automation/
├── agents/
│   └── tdd-worker.md          # TDD worker agent definition
└── commands/
    └── aad/
        ├── init.md            # Project initialization
        ├── plan.md            # Implementation plan generation
        ├── execute.md         # Wave-based execution
        ├── status.md          # Status check
        ├── cleanup.md         # Resource cleanup
        └── run.md             # End-to-end execution
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

## 🛠 Available Commands

### `/aad:init` - Project Initialization

```bash
/aad:init <project-dir> [parent-branch]
```

- Verify or initialize Git repository
- Create parent branch (default: `aad/develop`)
- Create worktree parent directory (`<project-dir>-wt/`)
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

### `/aad:cleanup` - Resource Cleanup

```bash
/aad:cleanup
```

- Remove worktrees
- Delete `feature/*` branches
- Archive state files

### `/aad:run` - End-to-End Execution

```bash
/aad:run <project-dir> <input-source> [parent-branch]
```

Auto-execute: `init` → `plan` → `execute` → `cleanup`

## 📖 Workflow Examples

### Step-by-Step Execution

```bash
# 1. Initialize
/aad:init ~/my-project

# 2. Generate plan (using kiro spec)
/aad:plan .kiro/specs/my-feature

# 3. Execute implementation
/aad:execute

# 4. Cleanup
/aad:cleanup
```

### End-to-End Execution

```bash
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

Each agent works in isolated worktree:

```
my-project/           # Parent branch
my-project-wt/
  ├── agent-order/    # feature/order branch
  ├── agent-portfolio/  # feature/portfolio branch
  └── agent-api/      # feature/api branch
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
  "worktreeDir": "/absolute/path/to/project-wt",
  "parentBranch": "aad/develop",
  "createdAt": "2026-02-18T00:00:00.000Z",
  "status": "initialized"
}
```

### `.claude/aad/plan.json`

Implementation plan (created during plan phase):

```json
{
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
