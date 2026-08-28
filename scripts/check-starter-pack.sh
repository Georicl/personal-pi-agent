#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
skill_root="$repo_root/Resources/StarterPack/skills"
agents_template="$repo_root/Resources/StarterPack/global/AGENTS.md"

test -f "$agents_template"

python3 - "$skill_root" <<'PY'
import json
import subprocess
import sys
import time

skill_root = sys.argv[1]
wanted = {
    "skill:project-start",
    "skill:code-change",
    "skill:research",
    "skill:knowledge-capture",
}

process = subprocess.Popen(
    ["pi", "--mode", "rpc", "--approve", "--no-session", "--skill", skill_root],
    cwd="/private/tmp",
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)
process.stdin.write(json.dumps({"id": "commands", "type": "get_commands"}) + "\n")
process.stdin.flush()

commands = []
deadline = time.time() + 10
while time.time() < deadline:
    line = process.stdout.readline()
    if not line:
        break
    payload = json.loads(line)
    if payload.get("type") == "response" and payload.get("id") == "commands":
        commands = payload.get("data", {}).get("commands", [])
        break

process.terminate()
try:
    process.wait(timeout=2)
except subprocess.TimeoutExpired:
    process.kill()

warnings = process.stderr.read().strip()
found = {
    command.get("name")
    for command in commands
    if command.get("source") == "skill"
}
missing = sorted(wanted - found)
result = {
    "skills": sorted(wanted & found),
    "missing": missing,
    "warnings": warnings,
}
print(json.dumps(result, indent=2))
if missing or warnings:
    raise SystemExit(1)
PY
