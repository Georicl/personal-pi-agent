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

auth_results = {}
blocked_fragments = ("credential", "token", "secret", "api_key", "apikey", "access", "refresh")

def contains_blocked_key(value):
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = str(key).lower()
            if any(fragment in normalized for fragment in blocked_fragments):
                return True
            if contains_blocked_key(child):
                return True
    elif isinstance(value, list):
        return any(contains_blocked_key(child) for child in value)
    return False

for provider in ("deepseek", "openai-codex"):
    completed = subprocess.run(
        ["pi", "auth", "check", "--provider", provider, "--json", "--no-refresh"],
        cwd="/private/tmp",
        text=True,
        capture_output=True,
        timeout=10,
        check=False,
    )
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    if not lines:
        raise SystemExit(f"Pi auth check returned no JSON for {provider}")
    payload = json.loads(lines[-1])
    if payload.get("status") not in {"ready", "not_ready"}:
        raise SystemExit(f"Unexpected Pi auth status for {provider}")
    if contains_blocked_key(payload):
        raise SystemExit(f"Pi auth check exposed a credential-shaped field for {provider}")
    auth_results[provider] = {
        key: payload[key]
        for key in ("status", "provider", "authType", "reason")
        if key in payload
    }

print(json.dumps({"auth": auth_results, "credentialsExposed": False}, indent=2))
PY
