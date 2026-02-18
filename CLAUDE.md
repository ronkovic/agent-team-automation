# agent-team-automation

Wave型並列実装の汎用ツールキット。複数のAIエージェントが並列でTDD開発を行い、Git worktreeで安全に分離・マージする。

## アーキテクチャ概要

```
commands/aad/     → ユーザー向けコマンド (/aad:init, /aad:plan, etc.)
agents/           → 専門エージェント定義 (tdd-worker, reviewer, etc.)
scripts/          → シェルスクリプト基盤 (Git操作、TDDパイプライン)
```

## コマンド

| コマンド | 説明 |
|---------|------|
| `/aad:init <dir> [feature-name]` | プロジェクト初期化・worktreeディレクトリ作成 |
| `/aad:plan <input>` | Wave型実装計画の生成 |
| `/aad:execute [wave]` | Wave実行・並列エージェント起動 |
| `/aad:review [base-ref]` | 並列コードレビュー + 自動修正 |
| `/aad:status` | 実行状態確認 |
| `/aad:cleanup [--orphans]` | リソースクリーンアップ |
| `/aad:run <dir> <input>` | エンドツーエンド実行 |

## エージェント

| エージェント | 役割 |
|------------|------|
| `tdd-worker` | TDDサイクルを実行する汎用ワーカー |
| `tester-red` | REDフェーズ専用：失敗テスト作成 |
| `implementer` | GREENフェーズ専用：最小実装 |
| `reviewer` | コードレビュー（カテゴリ別） |
| `merge-resolver` | マージ競合の論理的解決 |

## スクリプト

| スクリプト | 役割 |
|-----------|------|
| `scripts/worktree.sh` | Git worktree管理（create/remove/list/cleanup） |
| `scripts/tdd.sh` | TDDパイプライン（detect-framework/run-tests/commit-phase/merge-to-parent） |
| `scripts/plan.sh` | 計画ヘルパー（init/validate） |
| `scripts/cleanup.sh` | クリーンアップ（run/orphans） |

## Worktree命名パターン

worktreeベースディレクトリは `{project-dir}-{feature-name}-wt/` の形式で作成される。
`feature-name` は入力ソースから自動派生する:
- `.kiro/specs/auth-feature/` → `auth-feature`
- `requirements.md` → `requirements`
- プレーンテキスト入力 → `unnamed`

`feature-name` を省略した場合は後方互換性のため `{project-dir}-wt/` を使用。
これにより同一プロジェクトで複数のaad実行（異なるfeature）を同時に行える。

## 重要な注意事項

### スクリプト検出
コマンドは `SCRIPTS_DIR` 環境変数またはGitルートからスクリプトディレクトリを自動検出する。
スクリプトが見つからない場合はインラインGitコマンドにフォールバック。

### スピンロック
`tdd.sh merge-to-parent` はスピンロック（`aad-merge.lock`）を使用して並列マージを安全に直列化する。
タイムアウト: 120秒。

### TDD強制
`AAD_STRICT_TDD=true` 設定時、TDDサイクルをスキップしたエージェントはエラーになる。

### マージ競合
1. ロックファイルは `--theirs` で自動解決
2. ソースファイルの競合は `merge-resolver` エージェントが論理的に解決
3. 解決できない場合はユーザーに通知

### インストール
```bash
cp -r agents/* ~/.claude/agents/
cp -r commands/* ~/.claude/commands/
# scriptsはプロジェクトディレクトリに配置またはPATHに追加
```
