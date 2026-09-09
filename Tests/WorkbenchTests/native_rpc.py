"""Exercise real Pi tool registration and text revision handlers without a model."""
import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="pi-workbench-rpc-") as temporary:
    root = Path(temporary)
    result = root / "result.json"
    environment = dict(os.environ, PI_CODING_AGENT_DIR=str(root / "agent"),
                       PERSONAL_PI_WORKBENCH_TEST_RESULT=str(result))
    (root / "agent").mkdir()
    process = subprocess.Popen(["pi", "--mode", "rpc", "--offline", "--no-session", "--no-approve",
                                "--extension", str(repo / "Tests/Fixtures/workbench_extension.js")],
                               cwd=root, env=environment, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    def send(payload):
        process.stdin.write((json.dumps(payload) + "\n").encode())
        process.stdin.flush()

    try:
        send({"type": "prompt", "id": "smoke", "message": "/__personal_pi_test_workbench"})
        deadline = time.monotonic() + 30
        while not result.exists() and time.monotonic() < deadline:
            ready, _, _ = select.select([process.stdout], [], [], 0.2)
            if ready:
                line = process.stdout.readline()
                if not line:
                    break
                payload = json.loads(line)
                if payload.get("type") == "response" and not payload.get("success", True):
                    raise AssertionError(payload)
        assert result.exists(), "Native Workbench handlers did not finish"
        payload = json.loads(result.read_text())
        assert payload["first"]["details"]["personalPiTextArtifact"]["version"] == 1
        assert payload["revised"]["details"]["personalPiTextArtifact"]["version"] == 2
        assert json.loads(payload["loaded"]["content"][0]["text"])["content"] == "# Result\nOriginal evidence."
        assert payload["revised"]["details"]["personalPiTextArtifact"]["cwd"] == str(root.resolve())
        print("Native Workbench publish/read/revise passed")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        diagnostics = process.stderr.read().decode(errors="replace")
        assert "Failed to load extension" not in diagnostics, diagnostics
