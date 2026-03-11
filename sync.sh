#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$REPO_ROOT/.github/agents"
cp -r "$SCRIPT_DIR/.github/agents/." "$REPO_ROOT/.github/agents/"
# cp "$SCRIPT_DIR/.github/copilot-instructions.md" "$REPO_ROOT/.github/copilot-instructions.md"

echo "✅ AI instructions synced"
