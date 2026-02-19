---
name: aad-v2
description: Wave-based parallel TDD implementation toolkit. Invoke when the user wants to implement a feature using parallel agents, Wave分割, TDD development, or Agent Team automation. Triggered by phrases like "並列実装", "Wave実行", "aad run", "エージェントチーム", "TDD自動化", "Agent Team", "worktree並列", "TDD", "テスト駆動開発", "テスト駆動実装".
version: 2.0.0
---

# AAD v2 — Agent Team Automation

**IMPORTANT**: Always output responses in Japanese.

## 概要

複数のAIエージェントが並列でTDD開発を行い、Git worktreeで安全に分離・マージするWave型並列実装ツールキット。

## 起動方法

```
/aad [project-dir] <input-source> [options]
```

### 引数
- `[project-dir]`: 対象プロジェクトディレクトリ（省略時: カレント）
- `<input-source>`: 要件（ファイル・ディレクトリ・kiro spec・テキスト）
- `[parent-branch]`: 親ブランチ（省略時: `aad/develop`）

### オプション
- `--dry-run`: 計画生成のみ（実行なし）
- `--skip-review`: レビューをスキップ
- `--keep-worktrees`: 実行後のworktreeを保持
- `--workers N`: 最大並列数（デフォルト: 3）
- `--spec-only`: requirements.md生成後に停止

## ワークフロー

1. **Init** — Git/worktreeセットアップ・設定ファイル生成
2. **Plan** — コードベース調査（3並列）→ Wave分割計画生成 → Interface Contracts定義 → ユーザー承認
3. **Execute** — Wave 0（シーケンシャル bootstrap）+ Wave 1+（並列TDD）
4. **Review** — 並列コードレビュー + 自動修正（最大3ラウンド）
5. **PR** — Draft Pull Request作成
6. **Cleanup** — worktree/ブランチ削除・state.jsonアーカイブ

## エージェント構成

| エージェント | 役割 | モデル |
|------------|------|--------|
| `aad-tdd-worker` | TDDサイクル実行ワーカー | inherit |
| `aad-planner` | Wave計画生成・Interface Contracts | sonnet |
| `aad-reviewer` | 並列コードレビュー（Coordinator/単体） | sonnet |
| `aad-merge-resolver` | マージ競合の論理的解決 | sonnet |
| `investigator-structure` | コードベース構造・アーキテクチャ調査（Plan Phase） | general-purpose |
| `investigator-tests` | テスト状況・フレームワーク調査（Plan Phase） | general-purpose |
| `investigator-interfaces` | API・型定義・依存関係調査（Plan Phase） | general-purpose |

## 設定

**環境変数**:
- `AAD_SKIP_REVIEW=true`: レビューをスキップ
- `AAD_STRICT_TDD=true`: TDDサイクル未遵守をエラーに
- `AAD_WORKERS=N`: 並列数上限（デフォルト: 3）
- `AAD_SCRIPTS_DIR`: スクリプトディレクトリを明示指定

**設定ファイル** (`settings.local.json`):
Agent Teams 機能を有効化するために `.claude/settings.local.json` に配置:
```json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```
プラグイン同梱の `aad-v2/settings.local.json` をコピーするか、既存の設定ファイルに追記してください。

**スクリプト** (`${CLAUDE_PLUGIN_ROOT}/skills/aad/scripts/`):
- `deps.sh` — 言語別依存関係インストール（DRY集約）
- `worktree.sh` — Git worktree管理（symlink対応）
- `tdd.sh` — TDDパイプライン（spinlock merge）
- `plan.sh` — 計画検証
- `cleanup.sh` — リソースクリーンアップ
- `retry.sh` — 汎用リトライラッパー（指数バックオフ対応）
- `phase-gate.sh` — フェーズ間バリデーション

## 状態管理（3層ハイブリッド）

- **Layer 1**: `.claude/aad/state.json`（タスク単位・永続）
- **Layer 2**: Agent Teams TaskList（リアルタイム協調・一時）
- **Layer 3**: Git log（マージ済みコミット・権威ある記録）

詳細なオーケストレーター仕様は `/aad` コマンド (`commands/aad.md`) を参照。
