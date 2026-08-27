#!/usr/bin/env bash

set -euo pipefail

echo "Pi:   $(pi --version)"
echo "Node: $(node --version)"

python3 - <<'PY'
import json
import subprocess
import time

commands = [
    ("state", "get_state"),
    ("models", "get_available_models"),
    ("thinking", "get_available_thinking_levels"),
    ("commands", "get_commands"),
    ("tree", "get_tree"),
]

process = subprocess.Popen(
    ["pi", "--mode", "rpc", "--approve", "--no-session"],
    cwd="/private/tmp",
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

for request_id, command in commands:
    process.stdin.write(json.dumps({"id": request_id, "type": command}) + "\n")
process.stdin.flush()

pending = {request_id for request_id, _ in commands}
results = {}
deadline = time.time() + 15
while pending and time.time() < deadline:
    line = process.stdout.readline()
    if not line:
        break
    payload = json.loads(line)
    request_id = payload.get("id")
    if payload.get("type") == "response" and request_id in pending:
        results[request_id] = {
            "command": payload.get("command"),
            "success": payload.get("success"),
        }
        pending.remove(request_id)

process.terminate()
try:
    process.wait(timeout=3)
except subprocess.TimeoutExpired:
    process.kill()

print(json.dumps({"rpc": results, "missing": sorted(pending)}, indent=2))
if pending or not all(result["success"] for result in results.values()):
    raise SystemExit(1)
PY
