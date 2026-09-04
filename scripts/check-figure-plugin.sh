#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_root="$repo_root/Resources/PiPackages/Figure"
runtime_root="$package_root/runtime"
extension_path="$package_root/extensions/index.js"
skill_path="$package_root/skills/figure/SKILL.md"
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
  "$runtime_root/runner.py" \
  "$runtime_root/pyproject.toml" \
  "$runtime_root/uv.lock" \
  "$skill_path"; do
  [[ -f "$required" ]] || { echo "Missing Figure plugin resource: $required" >&2; exit 1; }
done

python3 - "$package_root/package.json" "$package_root/personal-pi-plugin.json" <<'PY'
import json
import sys
from pathlib import Path

package = json.loads(Path(sys.argv[1]).read_text())
plugin = json.loads(Path(sys.argv[2]).read_text())
assert package["name"] == "@personal-pi/figure", package
assert package["pi"]["extensions"] == ["extensions"], package
assert package["pi"]["skills"] == ["skills"], package
assert plugin["id"] == "figure", plugin
assert plugin["command"] == "figure", plugin
assert plugin["settingsNamespace"] == "figure", plugin
assert plugin["artifacts"][0]["kind"] == "figure", plugin
PY

uv lock --check --project "$runtime_root"
PYTHONPYCACHEPREFIX="$test_root/pycache" python3 -m py_compile "$runtime_root/runner.py"
node --check "$extension_path"

data_path="$test_root/example.csv"
artifact_root="$test_root/artifacts"
result_path="$test_root/render-result.json"
agent_root="$test_root/pi-agent"
managed_environment="$test_root/managed-environment"
mkdir -p "$agent_root"
printf '{"figure":{"keepWorkFiles":false}}\n' > "$agent_root/settings.json"
printf 'condition,time,value\ncontrol,0,1.1\ncontrol,1,1.8\ntreated,0,1.0\ntreated,1,2.6\n' > "$data_path"

inspect_result="$({
  python3 - "$data_path" <<'PY'
import json
import sys
print(json.dumps({"action": "inspect", "dataPath": sys.argv[1]}))
PY
} | UV_PROJECT_ENVIRONMENT="$managed_environment/.venv" uv run --quiet --project "$runtime_root" --locked python "$runtime_root/runner.py")"

python3 - "$inspect_result" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["success"] is True, payload
assert payload["inspection"]["data"]["rows"] == 4, payload
assert payload["inspection"]["data"]["columns"] == 3, payload
PY

UV_PROJECT_ENVIRONMENT="$managed_environment/.venv" uv run --quiet --project "$runtime_root" --locked python - "$runtime_root/runner.py" "$test_root" <<'PY'
import importlib.util
import sys
from pathlib import Path

import numpy as np
import pandas as pd

spec = importlib.util.spec_from_file_location("personal_pi_figure_runner", sys.argv[1])
runner = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(runner)
root = Path(sys.argv[2])
frame = pd.DataFrame({"group": ["a", "b"], "value": [1.0, 2.0]})
writers = {
    "sample.tsv": lambda path: frame.to_csv(path, sep="\t", index=False),
    "sample.xlsx": lambda path: frame.to_excel(path, index=False),
    "sample.ods": lambda path: frame.to_excel(path, index=False, engine="odf"),
    "sample.parquet": lambda path: frame.to_parquet(path, index=False),
    "sample.feather": lambda path: frame.to_feather(path),
    "sample.jsonl": lambda path: frame.to_json(path, orient="records", lines=True),
    "sample.pkl": lambda path: frame.to_pickle(path),
}
for name, write in writers.items():
    path = root / name
    write(path)
    loaded = runner.load_table(path)
    assert isinstance(loaded, pd.DataFrame), (name, type(loaded))
    assert loaded.shape == (2, 2), (name, loaded.shape)

npy = root / "sample.npy"
np.save(npy, np.array([[1, 2], [3, 4]]))
assert runner.load_table(npy).shape == (2, 2)
npz = root / "sample.npz"
np.savez(npz, first=np.array([1, 2]), second=np.array([3, 4]))
assert set(runner.load_table(npz)) == {"first", "second"}

limit_root = root / "iteration-limit"
for iteration in range(1, 6):
    (limit_root / f"v{iteration:03d}").mkdir(parents=True)
try:
    runner.next_iteration(limit_root, None)
except runner.FigureRequestError:
    pass
else:
    raise AssertionError("The five-iteration limit was not enforced")

failed_root = root / "failed-artifacts"
try:
    runner.render({
        "action": "render",
        "cwd": str(root),
        "artifactRoot": str(failed_root),
        "figureId": "failure-cleanup",
        "code": "value = 1",
    })
except runner.FigureRequestError:
    pass
else:
    raise AssertionError("A render without fig unexpectedly succeeded")
assert not list(failed_root.rglob(".work-*")), "Failed render left work files behind"
PY

{
  python3 - "$data_path" "$artifact_root" <<'PY'
import json
import sys
request = {
    "action": "render",
    "cwd": ".",
    "artifactRoot": sys.argv[2],
    "sessionId": "smoke-session",
    "title": "Figure plugin smoke test",
    "figureId": "smoke-figure",
    "iteration": 1,
    "dataPaths": [sys.argv[1]],
    "widthMm": 210,
    "heightMm": 74.25,
    "dpi": 300,
    "code": """fig, ax = plt.subplots(figsize=(width_mm / 25.4, height_mm / 25.4))\nsns.lineplot(data=data, x='time', y='value', hue='condition', marker='o', ax=ax)\nax.set_xlabel('Time (hours)')\nax.set_ylabel('Response (a.u.)')\nax.legend(title='Condition', frameon=False)\nfig.tight_layout()""",
}
print(json.dumps(request))
PY
} | UV_PROJECT_ENVIRONMENT="$managed_environment/.venv" uv run --quiet --project "$runtime_root" --locked python "$runtime_root/runner.py" > "$result_path"

UV_PROJECT_ENVIRONMENT="$managed_environment/.venv" uv run --quiet --project "$runtime_root" --locked python - "$result_path" <<'PY'
import json
import sys
from pathlib import Path
from PIL import Image

payload = json.loads(Path(sys.argv[1]).read_text())
assert payload["success"] is True, payload
artifact = payload["artifact"]
assert artifact["validation"]["passed"] is True, artifact["validation"]
assert artifact["intermediatesRetained"] is False
assert {item["format"] for item in artifact["files"]} == {"png", "tiff", "pdf"}

version_dir = Path(artifact["previewPath"]).parent
assert {path.name for path in version_dir.iterdir()} == {"figure.png", "figure.tiff", "figure.pdf"}
with Image.open(version_dir / "figure.png") as image:
    assert abs(image.width - 2480) <= 2, image.size
    assert abs(image.height - 877) <= 2, image.size
with Image.open(version_dir / "figure.tiff") as image:
    assert abs(image.width - 2480) <= 2, image.size
    assert abs(image.height - 877) <= 2, image.size
    dpi = image.info.get("dpi", (0, 0))
    assert abs(dpi[0] - 300) < 1 and abs(dpi[1] - 300) < 1, dpi
assert (version_dir / "figure.pdf").read_bytes().startswith(b"%PDF")
PY

python3 - "$package_root" "$agent_root" <<'PY'
import json
import os
import select
import subprocess
import sys
import time
from pathlib import Path

root = Path(sys.argv[1])
environment = dict(os.environ)
environment["PI_CODING_AGENT_DIR"] = sys.argv[2]
environment["PERSONAL_PI_FIGURE_ENVIRONMENT"] = str(Path(sys.argv[2]).parent / "managed-environment")
process = subprocess.Popen(
    [
        "pi", "--mode", "rpc", "--offline", "--no-session", "--no-approve",
        "--extension", str(root),
    ],
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
    assert "figure" in names, names
    assert "skill:figure" in names, names
    assert "__personal_pi_figure" in names, names

    runtime_result = Path(sys.argv[2]).parent / "runtime-result.json"
    command_payload = json.dumps({"responsePath": str(runtime_result)}).encode()
    import base64
    message = "/__personal_pi_figure " + base64.b64encode(command_payload).decode()
    process.stdin.write(json.dumps({"type": "prompt", "id": "runtime", "message": message}) + "\n")
    process.stdin.flush()
    deadline = time.monotonic() + 60
    accepted = False
    while time.monotonic() < deadline and not runtime_result.exists():
        readable, _, _ = select.select([process.stdout], [], [], 0.5)
        if readable:
            line = process.stdout.readline()
            if line:
                payload = json.loads(line)
                if payload.get("type") == "response" and payload.get("id") == "runtime":
                    accepted = payload.get("success") is True
    assert accepted, "Internal runtime check command was not accepted"
    assert runtime_result.exists(), "Internal runtime check did not return a result"
    checked = json.loads(runtime_result.read_text())
    assert checked.get("success") is True, checked
    assert checked["capabilities"]["defaultDpi"] == 300, checked
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

echo "Figure plugin check passed"
