# state.json スキーマ定義 (v1)

`.claude/aad/state.json` の正式スキーマ定義。
aad オーケストレーターがタスク単位の状態管理に使用する。

---

## Root Object

| フィールド | 型 | 必須 | 更新者 |
|-----------|-----|------|--------|
| `schemaVersion` | number | yes | aad.md (init) |
| `runId` | string | yes | aad.md (init) |
| `currentLevel` | number | yes | aad-phase-execute |
| `completedLevels` | number[] | yes | aad-phase-execute |
| `tasks` | object | yes | aad-phase-execute |
| `mergeLog` | array | yes | aad-phase-execute |
| `updatedAt` | string (ISO 8601) | yes | 全ライター |

### 例

```json
{
  "schemaVersion": 1,
  "runId": "20260218-143022",
  "currentLevel": 2,
  "completedLevels": [0, 1],
  "tasks": {
    "wave0-core": { "level": 0, "status": "completed", "completedAt": "2026-02-18T14:30:45Z" },
    "agent-order": { "level": 1, "status": "completed", "mergedAt": "2026-02-18T14:35:12Z" },
    "agent-user":  { "level": 1, "status": "failed", "failedAt": "2026-02-18T14:36:00Z", "reason": "test failures" }
  },
  "mergeLog": [
    { "agent": "agent-order", "mergedAt": "2026-02-18T14:35:12Z", "branch": "feature/agent-order" }
  ],
  "updatedAt": "2026-02-18T14:36:00Z"
}
```

---

## tasks.{key} オブジェクト

キーはエージェント名（例: `wave0-core`, `agent-order`）。

| フィールド | 型 | 必須 | 有効値 |
|-----------|-----|------|--------|
| `level` | number | yes | 0, 1, 2, ... |
| `status` | string | yes | `"pending"` `"completed"` `"failed"` `"retrying"` `"skipped"` |
| `completedAt` | string (ISO 8601) | conditional | `status == "completed"` 時 |
| `mergedAt` | string (ISO 8601) | conditional | マージ完了時 |
| `failedAt` | string (ISO 8601) | conditional | `status == "failed"` 時 |
| `reason` | string | optional | 失敗・スキップの理由（`error` フィールドは使わない） |
| `retried` | boolean | optional | リトライ済みフラグ |

---

## mergeLog 要素

| フィールド | 型 | 必須 |
|-----------|-----|------|
| `agent` | string | yes |
| `mergedAt` | string (ISO 8601) | yes |
| `branch` | string | yes |
| `conflictsResolved` | boolean | optional |

### 例

```json
{
  "agent": "agent-order",
  "mergedAt": "2026-02-18T14:35:12Z",
  "branch": "feature/agent-order",
  "conflictsResolved": false
}
```

---

## ステータスライフサイクル

```
pending
  │
  ├─[エージェント起動]──▶ retrying ──[成功]──▶ completed
  │                           │
  │                        [失敗]
  │                           │
  ├─[エージェント完了]──▶ completed    ▼
  │                        failed
  └─[依存失敗によりスキップ]──▶ skipped
```

| 遷移 | 条件 |
|------|------|
| `pending → retrying` | 初回失敗後、リトライ開始時 |
| `retrying → completed` | リトライ成功 |
| `retrying → failed` | リトライ上限到達 |
| `pending → completed` | 初回成功 |
| `pending → failed` | リトライなし失敗 |
| `pending → skipped` | 依存タスクが failed のためスキップ |

> **注記**: `skipped` はゲートチェック（post-execute）で失敗扱いされない。依存タスクの失敗によりスキップされたタスクは、復旧フロー（R-4）で依存元の再実行後に自動的に再評価される。

---

## バリデーション（phase-gate.sh post-init）

`phase-gate.sh post-init` は以下を検証する:

- `state.json` が存在する
- `runId` フィールドが存在する
- `schemaVersion` フィールドが存在する

---

## マイグレーション注記

### v0 → v1

- **`error` フィールドを廃止し `reason` に統一**

  古い形式（v0）:
  ```json
  { "status": "failed", "error": "test failures" }
  ```

  新しい形式（v1）:
  ```json
  { "status": "failed", "reason": "test failures", "failedAt": "..." }
  ```

- **`schemaVersion: 1` フィールドを追加**

既存の state.json（v0）は `schemaVersion` がないため phase-gate により検出される。
再実行時は `schemaVersion: 1` を手動追加するか、`/aad` コマンドを使って新規 run を開始すること。
