"""Deterministic Pi RPC peer: real pipes, delayed replies and lifecycle events.

No credentials, network calls or installed Pi are needed by these regressions.
"""
import json
import os
from pathlib import Path
import sys
import threading
import time

root = Path(sys.argv[1])
cwd = os.path.realpath(os.getcwd())
session_id = "initial-" + Path(cwd).name
if "--session" in sys.argv:
    header = json.loads(Path(sys.argv[sys.argv.index("--session") + 1]).read_text().splitlines()[0])
    session_id = header["id"]
    cwd = os.path.realpath(header["cwd"])
streaming = False
pending_count = 0
pending_dialog = None
write_lock = threading.Lock()


def emit(value):
    with write_lock:
        print(json.dumps(value), flush=True)


def later(seconds, callback):
    timer = threading.Timer(seconds, callback)
    timer.daemon = True
    timer.start()


def reply(request, data=None, delay=0):
    value = {"type": "response", "id": request["id"], "command": request["type"],
             "success": True, "data": data or {}}
    if delay:
        later(delay, lambda: emit(value))
    else:
        emit(value)


def start_model():
    global streaming, pending_count
    pending_count = 0
    streaming = True
    emit({"type": "agent_start"})


def finish_model():
    global streaming
    streaming = False
    emit({"type": "turn_end"})
    emit({"type": "agent_settled"})


for line in sys.stdin:
    request = json.loads(line)
    kind = request["type"]
    if kind == "get_state":
        reply(request, {"sessionId": session_id, "isStreaming": streaming,
                        "pendingMessageCount": pending_count, "messageCount": 1}, delay=0.12)
    elif kind == "get_messages":
        reply(request, {"messages": [{"id": "message-" + session_id, "role": "user",
                                      "content": [{"type": "text", "text": cwd}]}]}, delay=0.3)
    elif kind == "get_commands":
        reply(request, {"commands": [{"name": "notify", "source": "extension"}]})
    elif kind == "switch_session":
        header = json.loads(Path(request["sessionPath"]).read_text().splitlines()[0])
        if header["id"] == "veto":
            reply(request, {"cancelled": True}, delay=0.1)
        else:
            cwd = os.path.realpath(header["cwd"])
            session_id = header["id"]
            reply(request, {"cancelled": False}, delay=0.1)
    elif kind == "new_session":
        if (root / "ask-new").exists():
            pending_dialog = request
            emit({"type": "extension_ui_request", "id": "new-question", "method": "confirm", "title": "New session?"})
            continue
        cancelled = (root / "veto-new").exists()
        if not cancelled:
            session_id = "new-" + Path(cwd).name
        reply(request, {"cancelled": cancelled})
    elif kind == "prompt":
        text = request["message"]
        with (root / "prompts.jsonl").open("a") as stream:
            stream.write(json.dumps({"cwd": cwd, "text": text}) + "\n")
        if text == "/notify":
            emit({"type": "extension_ui_request", "id": "notice", "method": "notify", "message": "Status available"})
        elif text == "/ask":
            pending_dialog = request
            emit({"type": "extension_ui_request", "id": "question", "method": "confirm", "title": "Continue?"})
            continue
        elif text == "/late-ask":
            # Deterministic gate: the test first observes prompt+idle completion,
            # then creates this file to release the delayed UI request.
            def delayed_ui():
                while not (root / "release-late-ui").exists():
                    time.sleep(0.01)
                emit({"type": "extension_ui_request", "id": "late-question", "method": "confirm", "title": "Late question"})
            threading.Thread(target=delayed_ui, daemon=True).start()
        elif text == "/queue-model":
            pending_count = 1
            later(0.3, start_model)
            later(0.9, finish_model)
        elif text == "/instant":
            start_model()
            finish_model()
        else:
            start_model()
        reply(request)
    elif kind == "extension_ui_response":
        if pending_dialog:
            if pending_dialog["type"] == "new_session":
                reply(pending_dialog, {"cancelled": True}, delay=0.35)
            else:
                reply(pending_dialog)
            pending_dialog = None
    elif kind == "abort":
        finish_model()
        reply(request)
    else:
        reply(request)
