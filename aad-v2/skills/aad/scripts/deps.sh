#!/usr/bin/env bash
# deps.sh — 言語別依存関係インストール（DRY集約）
# 使用方法:
#   bash deps.sh install [project_dir]     # 直接実行
#   source deps.sh && deps_install [dir]   # source経由

deps_install() {
  local project_dir="${1:-.}"
  local orig_dir
  orig_dir=$(pwd)
  cd "$project_dir" || { echo "エラー: ディレクトリに移動できません: $project_dir" >&2; return 1; }

  local python=""

  # Python (uv優先 → python3フォールバック)
  if [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then
    if command -v uv >/dev/null 2>&1; then
      uv venv .venv 2>/dev/null || true
      local UV_INSTALL="uv pip install --python .venv/bin/python"
      if [ -f "pyproject.toml" ] && grep -q '\[.*test\]' pyproject.toml 2>/dev/null; then
        $UV_INSTALL -e ".[dev]" 2>/dev/null \
          || $UV_INSTALL -e ".[test]" 2>/dev/null \
          || $UV_INSTALL pytest
      elif [ -f "requirements.txt" ]; then
        $UV_INSTALL -r requirements.txt
      elif [ -f "setup.py" ]; then
        $UV_INSTALL -e . 2>/dev/null || $UV_INSTALL pytest
      else
        $UV_INSTALL pytest
      fi
      python=".venv/bin/python"
    elif command -v python3 >/dev/null 2>&1; then
      python3 -m pip install --user pytest 2>/dev/null || true
      python="python3"
    else
      echo "⚠ python3/uv 未検出 — Pythonテストはスキップ" >&2
    fi
    echo "Python実行環境: ${python:-未検出}"
  fi

  # Export python path for callers (Node.js/Go/Rust失敗に影響されないよう早期export)
  export AAD_PYTHON="${python}"

  # Node.js / TypeScript (ルート)
  if [ -f "package.json" ]; then
    if [ -f "pnpm-lock.yaml" ] && command -v pnpm >/dev/null 2>&1; then
      pnpm install
    elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
      yarn install
    elif command -v npm >/dev/null 2>&1; then
      npm install
    else
      echo "⚠ npm 未検出 — Node.jsテストはスキップ" >&2
    fi
  fi

  # Node.js / TypeScript (frontend/サブディレクトリ)
  if [ -f "frontend/package.json" ]; then
    if command -v npm >/dev/null 2>&1; then
      (cd frontend && npm install)
    else
      echo "⚠ npm 未検出 — frontend/のNode.jsテストはスキップ" >&2
    fi
  fi

  # Go (ルート)
  if [ -f "go.mod" ]; then
    command -v go >/dev/null 2>&1 && go mod download \
      || echo "⚠ go 未検出 — Goテストはスキップ" >&2
  fi

  # Go (backend/サブディレクトリ)
  if [ -f "backend/go.mod" ]; then
    command -v go >/dev/null 2>&1 && (cd backend && go mod download) \
      || echo "⚠ go 未検出 — backend/のGoテストはスキップ" >&2
  fi

  # Rust
  if [ -f "Cargo.toml" ]; then
    command -v cargo >/dev/null 2>&1 && cargo fetch 2>/dev/null \
      || echo "⚠ cargo 未検出 — Rustテストはスキップ" >&2
  fi

  # Ruby
  if [ -f "Gemfile" ]; then
    command -v bundle >/dev/null 2>&1 && bundle install \
      || echo "⚠ bundle 未検出 — Rubyテストはスキップ" >&2
  fi

  cd "$orig_dir"
}

# 直接実行サポート
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  case "${1:-install}" in
    install) deps_install "${2:-.}" ;;
    *) echo "使用方法: deps.sh install [project_dir]" >&2; exit 1 ;;
  esac
fi
