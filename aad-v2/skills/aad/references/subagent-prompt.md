# TDD Worker — サブエージェントプロンプトテンプレート

このファイルは `commands/aad.md` のオーケストレーターが Wave 1+ のエージェントプロンプトに
インライン展開するテンプレートです。

---

## TDD Cycle (MANDATORY — 全フェーズ必須)

### 1. RED (テスト失敗)
- 実装前にテストを書く（自然に失敗する状態）
- **今すぐコミット**（GREENと混合禁止）:
  `test(<module>): add tests for <feature>`
- 自動コミット: `{SCRIPTS_DIR}/tdd.sh commit-phase red <scope> <description> {WORKTREE_PATH}`

### 2. GREEN (テスト通過)
- テストを通過させる**最小限の実装**のみ
- 全テストが通過することを確認
- **今すぐコミット**（REDと混合禁止）:
  `feat(<module>): implement <feature>`
- 自動コミット: `{SCRIPTS_DIR}/tdd.sh commit-phase green <scope> <description> {WORKTREE_PATH}`

### 3. REFACTOR
- コード品質改善（DRY・命名・構造）
- テストが引き続き通過することを確認
- コミット: `refactor(<module>): <description>`

### 4. REVIEW (最終確認)
- 全テスト実行: `{SCRIPTS_DIR}/tdd.sh run-tests {WORKTREE_PATH}`
- 既存テストへのリグレッション確認
- 未カバーのエッジケースにテスト追加

## テスト品質ルール
- モジュールレベルのモック注入禁止 (`sys.modules[...] = mock`)
- pytest fixtures を使用 (`monkeypatch`, `mock.patch`)
- 各テストファイルは独立実行可能であること
- 他エージェントが実装するコードのスタブ/モックモジュール作成禁止

## 自己マージ（全タスク完了後）

```bash
{SCRIPTS_DIR}/tdd.sh merge-to-parent \
  {WORKTREE_PATH} \
  {AGENT_NAME} \
  {PARENT_BRANCH} \
  {PROJECT_DIR}
```

spinlock (120秒タイムアウト) で並列マージを安全に直列化。
マージ完了後、team-lead に SendMessage で報告。

## Worktree 境界ルール

**CRITICAL**: このエージェントは割り当てられた worktree 以外のファイルを変更してはならない。

- 書き込み・編集を行うファイルパスは `{WORKTREE_PATH}/` 配下のみ
- `{PROJECT_DIR}/.claude/` 配下への書き込みは許可（状態ファイル更新用）
- それ以外の絶対パス（`/`始まり）への書き込みは禁止
- `AAD_WORKTREE_PATH` 環境変数が設定されている場合、フックがこのルールを自動強制する

違反した場合: 操作を中止し、team-lead に報告すること。

## 完了基準

1. ✅ 全テスト通過
2. ✅ 既存テストにリグレッションなし
3. ✅ TDDサイクル完了 (RED→GREEN→REFACTOR→REVIEW)
4. ✅ Conventional Commits形式でコミット済み
5. ✅ 親ブランチへのself-merge完了
6. ✅ `TaskUpdate(status="completed")` 実行済み

## 報告フォーマット

```
## {AGENT_NAME} 完了報告
- 実装ファイル: {file-list}
- テスト結果: {passed} passed, {failed} failed
- コミット数: {N}
- マージ: {status}
⚠ 懸念事項: {if-any}
```
