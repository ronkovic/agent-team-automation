#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
使用方法: $(basename "$0") <サブコマンド> [引数...]

サブコマンド:
  init [<project_dir>]          プロジェクト情報を検出してJSON出力
  validate <plan_json_path>     plan.jsonを検証
EOF
  exit 1
}

cmd_init() {
  local project_dir="${1:-.}"

  # run IDを生成
  local run_id
  run_id=$(date +%Y%m%d-%H%M%S)

  # プロジェクトディレクトリの正規化
  project_dir=$(cd "$project_dir" && pwd)

  # プロジェクト名（ディレクトリ名）
  local project_name
  project_name=$(basename "$project_dir")

  # Gitリポジトリかチェック
  local current_branch=""
  if git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
    current_branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    echo "警告: ${project_dir} はGitリポジトリではありません" >&2
  fi

  # 使用言語の検出
  local language="unknown"
  if [[ -f "${project_dir}/package.json" ]]; then
    language="javascript/typescript"
  elif [[ -f "${project_dir}/pyproject.toml" ]] || [[ -f "${project_dir}/setup.py" ]] || [[ -f "${project_dir}/requirements.txt" ]]; then
    language="python"
  elif [[ -f "${project_dir}/go.mod" ]]; then
    language="go"
  elif [[ -f "${project_dir}/Cargo.toml" ]]; then
    language="rust"
  fi

  # JSON形式で出力
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg runId "$run_id" \
      --arg projectDir "$project_dir" \
      --arg projectName "$project_name" \
      --arg language "$language" \
      --arg currentBranch "$current_branch" \
      '{runId: $runId, projectDir: $projectDir, projectName: $projectName, language: $language, currentBranch: $currentBranch}'
  else
    python3 -c "
import json, sys
data = {
    'runId': sys.argv[1],
    'projectDir': sys.argv[2],
    'projectName': sys.argv[3],
    'language': sys.argv[4],
    'currentBranch': sys.argv[5]
}
print(json.dumps(data))" "$run_id" "$project_dir" "$project_name" "$language" "$current_branch"
  fi
}

cmd_validate() {
  local plan_json_path="${1:?エラー: plan.jsonのパスが必要です}"

  if [[ ! -f "$plan_json_path" ]]; then
    echo "エラー: ファイルが見つかりません: $plan_json_path"
    exit 1
  fi

  local errors=()

  if command -v jq >/dev/null 2>&1; then
    # jqを使った検証

    # 1. 重複タスクIDチェック（各agentのnameが一意）
    local agent_names
    agent_names=$(jq -r '.waves[].agents[]?.name' "$plan_json_path" 2>/dev/null || true)
    if [[ -n "$agent_names" ]]; then
      local duplicates
      duplicates=$(echo "$agent_names" | sort | uniq -d)
      if [[ -n "$duplicates" ]]; then
        errors+=("重複タスクID検出: $duplicates")
      fi
    fi

    # 2. 依存関係チェック（dependsOnに存在しないagentが指定されていないか）
    local all_names
    all_names=$(jq -r '.waves[].agents[]?.name' "$plan_json_path" 2>/dev/null | sort -u)
    local all_deps
    all_deps=$(jq -r '.waves[].agents[]?.dependsOn[]? // empty' "$plan_json_path" 2>/dev/null | sort -u)
    if [[ -n "$all_deps" ]]; then
      while IFS= read -r dep; do
        if ! echo "$all_names" | grep -Fqx "$dep"; then
          errors+=("依存関係エラー: '$dep' は存在しないagent名です")
        fi
      done <<< "$all_deps"
    fi

    # 3. ファイル競合チェック（複数のagentが同じファイルを担当していないか）
    local agent_count
    agent_count=$(jq '[.waves[].agents[]?] | length' "$plan_json_path" 2>/dev/null || echo "0")
    local all_files_with_owners=""
    for ((i=0; i<agent_count; i++)); do
      local agent_name_i
      agent_name_i=$(jq -r "[.waves[].agents[]?][$i].name" "$plan_json_path")
      local files_i
      files_i=$(jq -r "[.waves[].agents[]?][$i].files[]? // empty" "$plan_json_path" 2>/dev/null)
      if [[ -n "$files_i" ]]; then
        while IFS= read -r file; do
          # タブ区切りでファイルパスとエージェント名を結合（パスに : が含まれる場合の問題を回避）
          all_files_with_owners+="${file}"$'\t'"${agent_name_i}"$'\n'
        done <<< "$files_i"
      fi
    done

    if [[ -n "$all_files_with_owners" ]]; then
      local conflicting_files
      conflicting_files=$(echo "$all_files_with_owners" | cut -f1 | sort | uniq -d)
      if [[ -n "$conflicting_files" ]]; then
        while IFS= read -r conflict_file; do
          local owners
          owners=$(echo "$all_files_with_owners" | awk -F'\t' -v f="$conflict_file" '$1==f{print $2}' | tr '\n' ', ' | sed 's/,$//')
          errors+=("ファイル競合: '$conflict_file' が複数のagentに割り当てられています ($owners)")
        done <<< "$conflicting_files"
      fi
    fi

    # 4. apiContract位置チェック（ルートレベルに置かれていないか）
    if jq -e '.apiContract' "$plan_json_path" >/dev/null 2>&1; then
      errors+=("apiContract位置エラー: apiContractがルートレベルに配置されています。waves[N]内に配置してください")
    fi

    # 5. PATCHエンドポイントのsemanticsチェック
    local patch_no_sem
    patch_no_sem=$(jq '[.waves[]? | .apiContract?.endpoints[]? | select(.method == "PATCH") | select(.semantics == null)] | length' "$plan_json_path" 2>/dev/null || echo "0")
    if [[ "$patch_no_sem" -gt 0 ]]; then
      errors+=("apiContract内容エラー: PATCHエンドポイントに 'semantics' フィールドがありません")
    fi

    # 6. apiContract禁止キーチェック
    local forbidden
    forbidden=$(jq -r '[.waves[]?.apiContract? // empty | keys[] | select(. != "endpoints" and . != "errorFormat" and . != "sharedTypes")] | unique | .[]' "$plan_json_path" 2>/dev/null || true)
    if [[ -n "$forbidden" ]]; then
      errors+=("apiContract禁止キー: 許可キーは endpoints/errorFormat/sharedTypes のみ。不正: $forbidden")
    fi

    # 7. 空wavesチェック（警告のみ）
    local waves_count
    waves_count=$(jq '.waves | length' "$plan_json_path" 2>/dev/null || echo "0")
    if [[ "$waves_count" -eq 0 ]]; then
      echo "⚠ 警告: waves が空です" >&2
    fi
  else
    # jqがない場合はPythonで検証
    if ! command -v python3 >/dev/null 2>&1; then
      echo "エラー: jq または python3 が必要です" >&2
      exit 1
    fi
    python3 -c "
import json, sys

with open(sys.argv[1], 'r') as f:
    plan = json.load(f)

errors = []
agents = [a for w in plan.get('waves', []) for a in w.get('agents', [])]

# 1. 重複タスクIDチェック
names = [a['name'] for a in agents]
seen = set()
dups = set()
for n in names:
    if n in seen:
        dups.add(n)
    seen.add(n)
if dups:
    errors.append(f'重複タスクID検出: {list(dups)}')

# 2. 依存関係チェック
name_set = set(names)
for a in agents:
    for dep in a.get('dependsOn', []):
        if dep not in name_set:
            errors.append(f\"依存関係エラー: '{dep}' は存在しないagent名です\")

# 3. ファイル競合チェック
file_map = {}
for a in agents:
    for f in a.get('files', []):
        if f not in file_map:
            file_map[f] = []
        file_map[f].append(a['name'])
for f, owners in file_map.items():
    if len(owners) > 1:
        errors.append(f\"ファイル競合: '{f}' が複数のagentに割り当てられています ({', '.join(owners)})\")

# 4. apiContract位置チェック
if 'apiContract' in plan:
    errors.append('apiContract位置エラー: ルートレベルに配置されています。waves[N]内に移動してください')

# 5. PATCH semanticsチェック
for w in plan.get('waves', []):
    for ep in w.get('apiContract', {}).get('endpoints', []):
        if ep.get('method') == 'PATCH' and 'semantics' not in ep:
            errors.append(f\"apiContract内容エラー: PATCH {ep.get('path','?')} に semantics がありません\")

# 6. 禁止キーチェック
allowed = {'endpoints', 'errorFormat', 'sharedTypes'}
for w in plan.get('waves', []):
    c = w.get('apiContract')
    if c:
        bad = set(c.keys()) - allowed
        if bad: errors.append(f\"apiContract禁止キー: {bad}\")

if errors:
    for e in errors:
        print(f'✗ {e}')
    sys.exit(1)
else:
    print('✓ plan.json validation passed')
    sys.exit(0)
" "$plan_json_path" && exit 0 || exit 1
  fi

  # 結果出力
  if [[ ${#errors[@]} -gt 0 ]]; then
    echo "検証エラーが見つかりました:"
    for err in "${errors[@]}"; do
      echo "  ✗ $err"
    done
    exit 1
  else
    echo "✓ plan.json validation passed"
    exit 0
  fi
}

# メインエントリポイント
if [[ $# -lt 1 ]]; then
  usage
fi

subcommand="$1"
shift

case "$subcommand" in
  init)     cmd_init "$@" ;;
  validate) cmd_validate "$@" ;;
  *)
    echo "エラー: 不明なサブコマンド: $subcommand"
    usage
    ;;
esac
