#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
# Keep generated environments out of resources copied into the signed app.
export UV_PROJECT_ENVIRONMENT="$repo_root/.build/validation-envs/knowledge"
node --check Resources/PiPackages/Literature/extensions/index.js
uv run --quiet --locked --project Resources/PiPackages/Knowledge/runtime \
  python -m unittest discover -s Tests/LiteratureTests -p 'test_*.py' -v
uv run --quiet --locked --project Resources/PiPackages/Knowledge/runtime \
  python Tests/LiteratureTests/native_rpc.py
