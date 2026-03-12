#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$REPO_ROOT/.github"
cp -r "$SCRIPT_DIR/.github/." "$REPO_ROOT/.github/"
mv "$REPO_ROOT/.github/gitignore" "$REPO_ROOT/.github/.gitignore"

echo "✅ AI instructions synced"
