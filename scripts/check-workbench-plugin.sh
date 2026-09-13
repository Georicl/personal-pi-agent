#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node --check "$repo_root/Resources/PiPackages/Workbench/extensions/index.js"
node --test "$repo_root/Tests/WorkbenchTests/runtime.test.mjs"
python3 "$repo_root/Tests/WorkbenchTests/native_rpc.py"
