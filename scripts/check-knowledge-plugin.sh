#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_root="$repo_root/Resources/PiPackages/Knowledge"
extension_path="$package_root/extensions/index.js"
skill_path="$package_root/skills/knowledge/SKILL.md"
test_root="$(mktemp -d)"

cleanup() {
  if [[ -n "$test_root" && -d "$test_root" && "$test_root" != "/" ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

for required in \
  "$package_root/package.json" \
  "$package_root/personal-pi-plugin.json" \
  "$extension_path" \
  "$package_root/runtime/knowledge_core.py" \
  "$package_root/runtime/pyproject.toml" \
  "$package_root/runtime/uv.lock" \
  "$skill_path"; do
  [[ -f "$required" ]] || { echo "Missing Knowledge plugin resource: $required" >&2; exit 1; }
done

python3 - "$package_root/package.json" "$package_root/personal-pi-plugin.json" <<'PY'
import json
import sys
from pathlib import Path

package = json.loads(Path(sys.argv[1]).read_text())
plugin = json.loads(Path(sys.argv[2]).read_text())
assert package["name"] == "@personal-pi/knowledge", package
assert package["pi"]["extensions"] == ["extensions"], package
assert package["pi"]["skills"] == ["skills"], package
assert plugin["id"] == "knowledge", plugin
assert plugin["command"] == "knowledge", plugin
assert plugin["settingsNamespace"] == "knowledge", plugin
assert plugin["gui"]["artifactSidebar"] is False, plugin
PY

node --check "$extension_path"
scripts/check-knowledge-core.sh

agent_root="$test_root/pi/agent"
project_root="$test_root/project"
managed_environment="$test_root/managed-environment"
mkdir -p "$agent_root" "$project_root"

python3 - "$package_root" "$agent_root" "$project_root" "$managed_environment" <<'PY'
import base64
import json
import os
import select
import subprocess
import sys
import time
from pathlib import Path

package_root = Path(sys.argv[1])
agent_root = Path(sys.argv[2])
project_root = Path(sys.argv[3])
managed_environment = Path(sys.argv[4])
environment = dict(os.environ)
environment["PI_CODING_AGENT_DIR"] = str(agent_root)
environment["PERSONAL_PI_KNOWLEDGE_ENVIRONMENT"] = str(managed_environment)
process = subprocess.Popen(
    [
        "pi", "--mode", "rpc", "--offline", "--no-session", "--no-approve",
        "--extension", str(package_root),
    ],
    cwd=project_root,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
    env=environment,
)
try:
    assert process.stdin is not None and process.stdout is not None
    process.stdin.write(json.dumps({"type": "get_commands", "id": "commands"}) + "\n")
    process.stdin.flush()
    deadline = time.monotonic() + 20
    response = None
    while time.monotonic() < deadline:
        readable, _, _ = select.select([process.stdout], [], [], 0.5)
        if not readable:
            continue
        line = process.stdout.readline()
        if not line:
            break
        payload = json.loads(line)
        if payload.get("type") == "response" and payload.get("id") == "commands":
            response = payload
            break
    assert response and response.get("success") is True, response
    names = {item["name"] for item in response["data"]["commands"]}
    assert "knowledge" in names, names
    assert "skill:knowledge" in names, names
    assert "__personal_pi_knowledge" in names, names

    runtime_result = Path(sys.argv[3]).parent / "runtime-result.json"
    command_payload = json.dumps({"responsePath": str(runtime_result)}).encode()
    command = "/__personal_pi_knowledge " + base64.b64encode(command_payload).decode()
    process.stdin.write(json.dumps({"type": "prompt", "id": "runtime", "message": command}) + "\n")
    process.stdin.flush()
    deadline = time.monotonic() + 90
    accepted = False
    while time.monotonic() < deadline and not runtime_result.exists():
        readable, _, _ = select.select([process.stdout], [], [], 0.5)
        if not readable:
            continue
        line = process.stdout.readline()
        if not line:
            break
        payload = json.loads(line)
        if payload.get("type") == "response" and payload.get("id") == "runtime":
            accepted = payload.get("success") is True
    assert accepted, "Internal knowledge command was not accepted"
    assert runtime_result.exists(), "Internal knowledge runtime check did not return"
    checked = json.loads(runtime_result.read_text())
    assert checked.get("success") is True, checked
    assert checked["indexed"]["indexed"] == 1, checked
    assert checked["searched"]["results"][0]["chunk"]["locator"] == "Section: Runtime smoke", checked
    assert checked["inventory"]["fileCount"] == 1, checked
    index_path = Path(checked["indexed"]["scope"]["indexPath"])
    assert index_path.is_file(), index_path
    assert not index_path.is_relative_to(project_root), index_path
    assert not list(project_root.rglob("*.sqlite")), "Derived database leaked into project"
finally:
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
    assert process.stderr is not None
    diagnostics = process.stderr.read()
    assert "Invalid settings file" not in diagnostics, diagnostics
    assert "Failed to load extension" not in diagnostics, diagnostics
PY

echo "Knowledge plugin check passed"
