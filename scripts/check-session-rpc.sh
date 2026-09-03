#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
runtime_extension="$repo_root/Resources/personal-pi-runtime-extension.js"

python3 - "$runtime_extension" <<'PY'
import base64
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

extension_path = os.path.realpath(sys.argv[1])
if not os.path.isfile(extension_path):
    raise SystemExit(f"Runtime extension is missing: {extension_path}")

session_dir = tempfile.mkdtemp(prefix="personal-pi-session-rpc-")
process = subprocess.Popen(
    ["pi", "--mode", "rpc", "--approve", "--session-dir", session_dir, "--extension", extension_path],
    cwd=tempfile.gettempdir(),
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

counter = 0

def request(command_type, **fields):
    global counter
    counter += 1
    request_id = f"session-smoke-{counter}"
    payload = {"id": request_id, "type": command_type, **fields}
    process.stdin.write(json.dumps(payload) + "\n")
    process.stdin.flush()
    deadline = time.time() + 15
    while time.time() < deadline:
        line = process.stdout.readline()
        if not line:
            break
        response = json.loads(line)
        if response.get("type") == "response" and response.get("id") == request_id:
            if response.get("success") is not True:
                raise RuntimeError(response.get("error") or f"{command_type} failed")
            return response.get("data") or {}
    raise TimeoutError(f"Timed out waiting for {command_type}")

def flatten(nodes):
    result = []
    for node in nodes:
        result.append(node)
        result.extend(flatten(node.get("children") or []))
    return result

try:
    commands = request("get_commands").get("commands", [])
    names = {item.get("name") for item in commands}
    required = {"__personal_pi_navigate", "__personal_pi_reload"}
    if not required.issubset(names):
        raise RuntimeError(f"Internal commands were not loaded: {sorted(required - names)}")

    request("bash", command="printf first")
    request("bash", command="printf second")
    initial = request("get_tree")
    entries = flatten(initial.get("tree") or [])
    if len(entries) < 2:
        raise RuntimeError("Pi did not create the expected session tree entries")

    target_id = entries[0]["entry"]["id"]
    encoded = base64.b64encode(json.dumps({
        "entryId": target_id,
        "summarize": False,
    }).encode()).decode()
    request("prompt", message=f"/__personal_pi_navigate {encoded}")
    navigated = request("get_tree")
    if navigated.get("leafId") != target_id:
        raise RuntimeError("Internal tree navigation did not update the active leaf")

    request("prompt", message="/__personal_pi_reload")
    names_after_reload = {
        item.get("name") for item in request("get_commands").get("commands", [])
    }
    if not required.issubset(names_after_reload):
        raise RuntimeError("Internal commands disappeared after reload")

finally:
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
    shutil.rmtree(session_dir, ignore_errors=True)

print("Pi session RPC and internal runtime extension checks passed.")
PY
