#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runtime_root="$repo_root/Resources/PiPackages/Knowledge/runtime"
test_source_root="$repo_root/Tests/KnowledgeCoreTests"
test_root="$(mktemp -d)"
export UV_PROJECT_ENVIRONMENT="$test_root/venv"

cleanup() {
  if [[ -n "$test_root" && -d "$test_root" && "$test_root" != "/" ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

for required in \
  "$runtime_root/knowledge_core.py" \
  "$runtime_root/schema.sql" \
  "$runtime_root/pyproject.toml" \
  "$runtime_root/uv.lock" \
  "$test_source_root/test_knowledge_core.py"; do
  [[ -f "$required" ]] || { echo "Missing Knowledge Core resource: $required" >&2; exit 1; }
done

uv lock --check --project "$runtime_root"
PYTHONPYCACHEPREFIX="$test_root/pycache" \
  uv run --quiet --project "$runtime_root" --locked \
  python -m py_compile "$runtime_root/knowledge_core.py"
PYTHONPATH="$runtime_root" PYTHONPYCACHEPREFIX="$test_root/pycache" \
  uv run --quiet --project "$runtime_root" --locked \
  python -m unittest discover -s "$test_source_root" -p 'test_*.py' -v

PYTHONPYCACHEPREFIX="$test_root/pycache" \
  uv run --quiet --project "$runtime_root" --locked \
  python - "$runtime_root/knowledge_core.py" "$test_root" <<'PY'
import json
import sqlite3
import subprocess
import sys
from pathlib import Path

runner = Path(sys.argv[1])
root = Path(sys.argv[2])
pi_root = root / "pi"
project_root = root / "project"
source_root = project_root / ".pi" / "knowledge" / "sources"
source_root.mkdir(parents=True)
(source_root / "smoke.md").write_text(
    "# Provenance\n\nKnowledge retrieval keeps exact source locators.",
    encoding="utf-8",
)

def call(request):
    process = subprocess.run(
        [sys.executable, str(runner)],
        input=json.dumps(request),
        text=True,
        capture_output=True,
        check=True,
    )
    payload = json.loads(process.stdout)
    assert payload["success"] is True, payload
    return payload

scope = {"kind": "project", "projectRoot": str(project_root)}
indexed = call({"action": "index", "piRoot": str(pi_root), "scope": scope})
assert indexed["indexed"] == 1, indexed
searched = call({
    "action": "search",
    "piRoot": str(pi_root),
    "query": "exact source locators",
    "scopes": [scope],
})
assert searched["results"][0]["chunk"]["locator"] == "Section: Provenance", searched
index_path = Path(indexed["scope"]["indexPath"])
with sqlite3.connect(index_path) as connection:
    assert connection.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    assert connection.execute("PRAGMA foreign_key_check").fetchall() == []
PY

echo "Knowledge Core check passed"
