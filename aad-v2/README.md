# AAD v2 — Agent Team Automation Plugin

Wave型並列実装の Claude Code Plugin。複数のAIエージェントが並列でTDD開発を行い、Git worktreeで安全に分離・マージする。

## 前バージョンからの主な改善点

| 改善 | 詳細 |
|------|------|
| **Plugin化** | `.claude-plugin/plugin.json` で公式Plugin形式に準拠 |
| **SKILL.md / command分離** | SKILL.md は概要のみ (常時ロード最小化)、オーケストレーターは commands/aad.md |
| **deps.sh による DRY化** | 依存インストールコード (~75行) を5箇所から1箇所に集約 |
| **タスク単位の状態管理** | state.json をWave単位→タスク単位に変更（部分再実行可能） |
| **Interface Contracts** | requirements.md にAPI契約テーブルを追加、Wave 0 で共有型ファイル生成 |
| **symlink対応** | worktree.sh に `setup-symlinks` を追加（node_modules/.venv等を共有） |
| **エージェント100行制限** | tdd-worker/reviewer を各100行以内に抑制 |
| **Review + PR** | Wave後レビューと最終レビューをオーケストレーターに統合 |
| **Codebase Investigation** | Plan Phase で3エージェント並列調査（構造・テスト・インターフェース）、計画精度向上 |

## ディレクトリ構成

```
aad-v2/
  .claude-plugin/plugin.json      # Plugin設定
  settings.local.json             # Agent Teams 有効化設定
  hooks/
    README.md                     # フック設定ガイド
    memory-check.sh               # Hook A: メモリ安全チェック
    worktree-boundary.sh          # Hook B: Worktree境界チェック
  skills/aad/
    SKILL.md                      # 概要・トリガー条件（常時ロード、~100行）
    references/
      subagent-prompt.md          # TDD Workerプロンプトテンプレート
      review-process.md           # Review Coordinatorプロセス定義
      investigation-guide.md      # コードベース調査エージェント指示（3エージェント定義）
    scripts/
      deps.sh                     # 依存関係インストール（DRY集約）
      worktree.sh                 # Git worktree管理（symlink対応）
      tdd.sh                      # TDDパイプライン（spinlock merge）
      plan.sh                     # 計画検証
      cleanup.sh                  # リソースクリーンアップ
  commands/
    aad.md                        # メインオーケストレーター
  agents/
    aad-tdd-worker.md             # TDDワーカー（<100行）
    aad-planner.md                # Wave計画生成（調査機能付き）
    aad-reviewer.md               # 並列コードレビュー（<100行）
    aad-merge-resolver.md         # マージ競合解決（~65行）
```

## インストール

```bash
# Claude Code Plugin として配置
cp -r aad-v2/ ~/.claude/plugins/

# Agent Teams 機能を有効化（必須）
cp aad-v2/settings.local.json ~/.claude/settings.local.json
# 既存の settings.local.json がある場合は env セクションのみ追記してください

# スクリプトを直接使う場合（プロジェクトに配置）
cp -r aad-v2/skills/aad/scripts/* path/to/project/scripts/
```

### tmux モード（オプション）

tmux がインストールされている環境では、teammate モードを tmux に変更するとターミナル分割で視覚的に確認できます:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "tmux"
}
```

デフォルトの background モードは tmux 不要でほぼすべての環境で動作します。

### Hooks（オプション）

安全フックを有効化するには `hooks/README.md` の手順に従い `.claude/hooks.json` を設定してください:

```bash
# フックスクリプトを確認
cat ~/.claude/plugins/aad-v2/hooks/README.md
```

## 使い方

```bash
# 基本（カレントディレクトリのrequirements.mdを使用）
/aad requirements.md

# Kiro spec を使用
/aad .kiro/specs/auth-feature

# 別プロジェクトを指定
/aad ./my-project requirements.md

# オプション
/aad requirements.md --dry-run        # 計画のみ生成
/aad requirements.md --skip-review    # コードレビューをスキップ
/aad requirements.md --keep-worktrees # worktreeを保持
```

## 環境変数

| 変数 | 説明 |
|------|------|
| `AAD_SKIP_REVIEW=true` | コードレビューをスキップ |
| `AAD_STRICT_TDD=true` | TDDサイクル未遵守をエラー扱い |
| `AAD_WORKERS=N` | 最大並列数（デフォルト: 3） |
| `AAD_SCRIPTS_DIR` | スクリプトディレクトリの明示指定 |

## 状態管理（3層ハイブリッド）

| レイヤー | 役割 | 永続性 |
|---------|------|--------|
| `state.json` (タスク単位) | 失敗タスク特定・部分再実行 | ✓ セッション跨ぎ可 |
| Agent Teams TaskList | リアルタイム協調 | ✗ セッション内のみ |
| Git log | マージ済みコミット（権威ある記録） | ✓ 永続 |

### state.json 形式

```json
{
  "runId": "20260218-143022",
  "currentLevel": 2,
  "completedLevels": [0, 1],
  "tasks": {
    "wave0-core": { "level": 0, "status": "completed", "completedAt": "..." },
    "agent-order": { "level": 1, "status": "completed", "mergedAt": "..." },
    "agent-portfolio": { "level": 1, "status": "failed", "error": "test failures" }
  },
  "mergeLog": [...]
}
```

## Codebase Investigation（既存プロジェクト向け）

Plan Phase で既存コードベースを自動調査し、計画精度を向上させます（ファイル数 ≥ 10 の場合）。

### 3 並列調査エージェント

| エージェント | 調査内容 | 出力ファイル |
|------------|---------|------------|
| `investigator-structure` | ディレクトリ構造・アーキテクチャパターン・主要モジュール | `.claude/aad/investigation/structure.md` |
| `investigator-tests` | テストフレームワーク・カバレッジ・テストパターン | `.claude/aad/investigation/tests.md` |
| `investigator-interfaces` | API エンドポイント・型定義・モジュール依存グラフ | `.claude/aad/investigation/interfaces.md` |

### 効果

- 既存のアーキテクチャパターンを踏襲した実装計画を生成
- 既存インターフェースの破壊的変更を防止
- 既存テストパターンに合わせたテストケース設計
- モジュール間依存関係に基づいた最適な Wave 割当

## Interface Contracts

requirements.md にテーブル形式で定義（JSON スキーマ不要）:

```markdown
## Interface Contracts

### API Endpoints
| Method | Path | Request | Response | Notes |
|--------|------|---------|----------|-------|
| POST | /api/orders | { symbol, qty } | Order | 新規作成 |
| PATCH | /api/orders/:id | { qty?, status? } | Order | 部分更新 |

### Shared Types
- Order: { id: number, symbol: string, quantity: number, status: "active"|"filled" }
```

Wave 0 でこの定義から共有型ファイル（`src/types/api.ts` 等）を生成する。
