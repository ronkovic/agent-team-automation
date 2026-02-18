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
  elif [[ -f "${project_dir}/pyproject.toml" ]] || [[ -f "${project_dir}/setup.py" ]]; then
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
    cat <<JSONEOF
{"runId": "$run_id", "projectDir": "$project_dir", "projectName": "$project_name", "language": "$language", "currentBranch": "$current_branch"}
JSONEOF
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
    agent_names=$(jq -r '.agents[].name' "$plan_json_path" 2>/dev/null || true)
    if [[ -n "$agent_names" ]]; then
      local duplicates
      duplicates=$(echo "$agent_names" | sort | uniq -d)
      if [[ -n "$duplicates" ]]; then
        errors+=("重複タスクID検出: $duplicates")
      fi
    fi

    # 2. 依存関係チェック（dependsOnに存在しないagentが指定されていないか）
    local all_names
    all_names=$(jq -r '.agents[].name' "$plan_json_path" 2>/dev/null | sort -u)
    local all_deps
    all_deps=$(jq -r '.agents[].dependsOn[]? // empty' "$plan_json_path" 2>/dev/null | sort -u)
    if [[ -n "$all_deps" ]]; then
      while IFS= read -r dep; do
        if ! echo "$all_names" | grep -qx "$dep"; then
          errors+=("依存関係エラー: '$dep' は存在しないagent名です")
        fi
      done <<< "$all_deps"
    fi

    # 3. ファイル競合チェック（複数のagentが同じファイルを担当していないか）
    local agent_count
    agent_count=$(jq '.agents | length' "$plan_json_path" 2>/dev/null || echo "0")
    local all_files_with_owners=""
    for ((i=0; i<agent_count; i++)); do
      local agent_name_i
      agent_name_i=$(jq -r ".agents[$i].name" "$plan_json_path")
      local files_i
      files_i=$(jq -r ".agents[$i].files[]? // empty" "$plan_json_path" 2>/dev/null)
      if [[ -n "$files_i" ]]; then
        while IFS= read -r file; do
          all_files_with_owners+="${file}:${agent_name_i}"$'\n'
        done <<< "$files_i"
      fi
    done

    if [[ -n "$all_files_with_owners" ]]; then
      local conflicting_files
      conflicting_files=$(echo "$all_files_with_owners" | sed 's/:.*$//' | sort | uniq -d)
      if [[ -n "$conflicting_files" ]]; then
        while IFS= read -r conflict_file; do
          local owners
          owners=$(echo "$all_files_with_owners" | grep "^${conflict_file}:" | sed 's/^.*://' | tr '\n' ', ' | sed 's/,$//')
          errors+=("ファイル競合: '$conflict_file' が複数のagentに割り当てられています ($owners)")
        done <<< "$conflicting_files"
      fi
    fi
  else
    # jqがない場合はPythonで検証
    python3 -c "
import json, sys

with open('$plan_json_path', 'r') as f:
    plan = json.load(f)

errors = []
agents = plan.get('agents', [])

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

if errors:
    for e in errors:
        print(f'✗ {e}')
    sys.exit(1)
else:
    print('✓ plan.json validation passed')
    sys.exit(0)
" && exit 0 || exit 1
    return
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
