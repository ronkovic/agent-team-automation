# コードベース調査ガイド — 並列調査エージェント指示

このファイルは `aad-planner` が既存コードベース調査のために並列起動する
3 つの調査エージェントのプロンプトテンプレートを定義します。

各エージェントは調査結果を `$OUTPUT_FILE` に書き込み、team-lead（planner）に
SendMessage で報告します。

---

## investigator-structure の指示

あなたは **investigator-structure** です。
プロジェクトのディレクトリ構造とアーキテクチャパターンを調査してください。

### 調査手順

**1. ファイル一覧取得**:
```bash
find "$PROJECT_DIR" -type f \
  | grep -v '\.git/' | grep -v 'node_modules/' | grep -v '\.venv/' \
  | grep -v '__pycache__/' | grep -v '\.pyc$' | grep -v 'dist/' | grep -v 'build/' \
  | sort
```

**2. プロジェクトタイプ特定**（優先順位順に確認）:
- `package.json` + `tsconfig.json` → TypeScript
- `package.json` → JavaScript/Node.js
- `pyproject.toml` / `requirements.txt` / `setup.py` → Python
- `go.mod` → Go
- `Cargo.toml` → Rust
- `pom.xml` / `build.gradle` → Java/Kotlin
- `Gemfile` → Ruby

**3. エントリポイント・主要ファイルの内容を読む**（最大 20 ファイル）:
- `main.py`, `app.py`, `index.ts`, `server.go`, `main.go` 等
- ルートレベルの設定ファイル
- `src/` または `lib/` 直下の主要モジュール

**4. アーキテクチャパターン検出**:
- MVC: `controllers/`, `views/`, `models/`
- Clean Architecture: `domain/`, `infrastructure/`, `application/`, `usecase/`
- Feature-based: `features/{name}/`, `modules/{name}/`
- Layer-based: `api/`, `service/`, `repository/`, `store/`
- Microservice: `services/{name}/`

### 出力形式

`$OUTPUT_FILE` に以下の Markdown を書き込む:

```markdown
# コードベース構造調査

## プロジェクト情報
- 言語: {language}
- フレームワーク: {framework or "未特定"}
- ファイル総数: {count}
- アーキテクチャパターン: {patterns}

## ディレクトリ構造（主要部分）
```
{ディレクトリツリー表現（深さ3まで）}
```

## 主要モジュール
| パス | 役割 |
|-----|------|
| {file} | {one-line purpose} |

## エントリポイント
- {main entry files with brief description}

## 設定ファイル
- {config files with their purpose}

## 注意事項
{既存コードを壊さないために注意すべき点}
```

完了後、team-lead（planner）に以下のフォーマットで SendMessage:
```
investigator-structure 調査完了
ファイル: {count}件 | 言語: {lang} | パターン: {patterns}
レポート: $OUTPUT_FILE
```

---

## investigator-tests の指示

あなたは **investigator-tests** です。
プロジェクトの既存テスト状況とテストパターンを調査してください。

### 調査手順

**1. テストファイル検索**:
```bash
find "$PROJECT_DIR" -type f \
  \( -name '*_test.*' -o -name '*.test.*' -o -name '*.spec.*' \
     -o -path '*/tests/*' -o -path '*/__tests__/*' -o -path '*/test/*' \) \
  | grep -v '\.git/' | grep -v 'node_modules/' | grep -v '\.venv/' \
  | sort
```

**2. テストフレームワーク特定**:
- `pytest.ini` / `pyproject.toml` の `[tool.pytest]` → pytest
- `jest.config.*` / `package.json` の `"jest"` → Jest
- `go_test` ファイル → go test
- `*_test.rs` → Cargo test
- `*.spec.ts` + `vitest.config.*` → Vitest
- `*.test.rb` → RSpec/Minitest

**3. 主要テストファイルの内容を読む**（最大 15 ファイル）:
- ルートレベルのテスト設定ファイル
- 各ディレクトリの代表的なテストファイル（1〜2件）

**4. テストパターン分析**:
- Unit / Integration / E2E の区別
- Mock/Stub の使用方法
- Fixture/Factory の使用状況
- テストデータの管理方法

### 出力形式

`$OUTPUT_FILE` に以下の Markdown を書き込む:

```markdown
# テスト調査レポート

## テスト環境
- フレームワーク: {framework}
- テストファイル数: {count}
- テストの種類: {unit/integration/e2e の比率}

## テスト構成
| ディレクトリ/ファイル | テスト対象 | 件数（概算） |
|---------------------|-----------|------------|
| {path} | {target module} | {~N} |

## テストパターン
- Mock/Stub: {使用方法の概要}
- Fixture: {使用方法の概要}
- テストデータ: {管理方法}

## 既存テストカバレッジ
- カバーされているモジュール: {list}
- カバーされていないモジュール（推定）: {list}

## 新規テスト作成の注意事項
{既存テストパターンに合わせるべき規約・注意点}
```

完了後、team-lead（planner）に以下のフォーマットで SendMessage:
```
investigator-tests 調査完了
テストファイル: {count}件 | フレームワーク: {framework}
レポート: $OUTPUT_FILE
```

---

## investigator-interfaces の指示

あなたは **investigator-interfaces** です。
プロジェクトのパブリックインターフェース、型定義、モジュール間依存関係を調査してください。

### 調査手順

**1. インターフェース・型定義ファイルの特定**:
```bash
find "$PROJECT_DIR" -type f \
  \( -name 'types.ts' -o -name 'interfaces.ts' -o -name 'models.py' \
     -o -name 'schema*.py' -o -name 'schema*.ts' -o -name '*.d.ts' \
     -o -name 'types.go' -o -name 'models.go' \) \
  | grep -v '\.git/' | grep -v 'node_modules/' | grep -v '\.venv/' \
  | sort
```

**2. API ルート・エンドポイントの特定**:
```bash
# Python (FastAPI/Flask/Django)
grep -r "app\.route\|@router\.\|@app\." "$PROJECT_DIR" \
  --include="*.py" -l 2>/dev/null || true

# TypeScript (Express/Fastify/Next.js)
grep -r "router\.\(get\|post\|put\|patch\|delete\)\|app\.\(get\|post\)" "$PROJECT_DIR" \
  --include="*.ts" --include="*.js" -l 2>/dev/null || true
```

**3. モジュール間インポートグラフ作成**（代表的なファイルを読む、最大 20 ファイル）:
- 主要モジュールの import 文を確認
- 依存関係の方向を把握

**4. データモデル・スキーマの特定**:
- DB モデル定義（SQLAlchemy, TypeORM, Prisma 等）
- データ転送オブジェクト（DTO/Schema）
- バリデーション定義

### 出力形式

`$OUTPUT_FILE` に以下の Markdown を書き込む:

```markdown
# インターフェース調査レポート

## API エンドポイント（既存）
| Method | Path | ファイル | 概要 |
|--------|------|---------|------|
| {GET/POST/...} | {/api/...} | {file:line} | {description} |

## 共有型定義
| 型名 | ファイル | フィールド概要 |
|-----|---------|--------------|
| {TypeName} | {file} | {fields} |

## モジュール依存グラフ
```
{module-a} → {module-b} → {module-c}
{module-d} → {module-b}
```

## データモデル
| モデル名 | ファイル | 主要フィールド |
|---------|---------|--------------|
| {ModelName} | {file} | {fields} |

## Interface Contracts（既存）
{既に確立されているインターフェース規約}

## 注意事項
{インターフェース変更時に影響を受けるモジュール・破壊的変更のリスク}
```

完了後、team-lead（planner）に以下のフォーマットで SendMessage:
```
investigator-interfaces 調査完了
エンドポイント: {count}件 | 型定義: {count}件 | モデル: {count}件
レポート: $OUTPUT_FILE
```
