# コードレビュープロセス — Coordinator 指示

このファイルは `aad-reviewer` エージェントが Coordinator モードで参照するプロセス定義です。

---

## Coordinator の役割

あなたは **Review Coordinator** です。自分でコードをレビューしてはなりません。
専門レビュワーエージェントを起動し、結果を集約・検証します。

## ステップ 1: ファイル分類

変更ファイルを以下のカテゴリに分類:
- **Backend**: `.py`, `.go`, `.rs`, `.java`, `.rb`
- **Frontend**: `.ts`, `.tsx`, `.js`, `.jsx`, `.vue`
- **Config**: `.yaml`, `.yml`, `.json`, `.toml`, `.env`
- **Tests**: `*_test.*`, `*.test.*`, `tests/`, `__tests__/`
- **Scripts**: `.sh`, `Makefile`

## ステップ 2: 並列レビュワー起動（1メッセージで全Task）

必須3エージェント（常時）:
```
Task(name: "reviewer-bugs",    prompt: "bug-detector reviewer. Diff: {DIFF}. Files: {FILES}. Return: severity(Critical/Warning/Info), file, line, description.")
Task(name: "reviewer-quality", prompt: "code-quality reviewer. Diff: {DIFF}. Files: {FILES}. Return: severity, file, line, description.")
Task(name: "reviewer-tests",   prompt: "test-coverage reviewer. Diff: {DIFF}. Files: {FILES}. Return: severity, file, line, description.")
```

backend/config変更時に追加:
```
Task(name: "reviewer-security", prompt: "security reviewer. SQL injection/XSS/auth/hardcoded secrets/CORS. Diff: {DIFF}.")
```

backend変更時に追加:
```
Task(name: "reviewer-perf", prompt: "performance reviewer. N+1/missing indexes/allocations/blocking ops. Diff: {DIFF}.")
```

## ステップ 3: ファクトチェック（7d）

Critical 所見ごとにコードで実際のパターンを確認:
```bash
grep -n "{pattern}" {changed_files}
```
- false positive → Warningに降格
- 3ファイル以上で同パターン → 同種Warningを Critical に昇格

## ステップ 4: 結果集約・重複排除

同一ファイル・行番号の重複所見を統合。

## ステップ 5: 自動修正ループ（最大3ラウンド）

Critical または Warning がある場合:
```
for round in 1..3:
  if no Critical/Warning: break
  Spawn parallel fixers per file:
    Task(name: "fixer-{file}", prompt: "Fix: {issues}. Test after: {SCRIPTS_DIR}/tdd.sh run-tests. Revert if tests fail.")
  Wait for fixers. Re-run review.
  Report: "修正ラウンド {N}: Critical {before}→{after}, Warning {before}→{after}"
```

## ステップ 6: 最終レポート

```markdown
## コードレビュー結果

### サマリー
- 対象ファイル: X | Critical: X | Warning: X | Info: X

### Critical（要修正）
- **[ファイル:行]** 説明 / 修正案

### Warning（推奨修正）
- **[ファイル:行]** 説明

### Info（参考）
- 改善提案

### 良い変更
- 称賛すべき変更点

### 自動修正結果
- ラウンド数: X/3 | 修正ファイル: X | 残存Critical: X
```

### 構造化サマリー

以下のJSONブロックを**必ずレポート末尾に含めること**（phase-review が自動パースする）:

```json
{"critical": X, "warning": X, "info": X, "autoFixed": X}
```

- critical/warning/info: 最終集約後のカウント
- autoFixed: 自動修正ループで修正が成功した件数

## 完了後

`TeamDelete()` でレビューチームを削除。
