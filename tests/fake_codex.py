#!/usr/bin/env python3
"""A fake `codex app-server --stdio` for offline tests.

Speaks just enough of the app-server JSON-RPC protocol for does-gpt-cheat's probe runner. Behaviour is
controlled by environment variables:
  FAKE_CODEX_MODEL        model label whose reference text is returned (default gpt-6-astra)
  FAKE_CODEX_THREAD_MODEL model reported for the target thread (default = FAKE_CODEX_MODEL)
  FAKE_CODEX_TOOL=1       the probe "tries a tool" (item/started commandExecution) → must be rejected
  FAKE_CODEX_FAIL=1       the turn ends with status failed
  FAKE_CODEX_APPROVAL=1   the server sends an approval request during the turn
  FAKE_CODEX_LOG=path     append every received message here
"""
import json
import os
import sys
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(HERE, "fixtures", "reference_subset.jsonl")


def texts_for(model):
    out = []
    with open(FIXTURE, "r", encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            if row["model_id"] == model:
                out.append(row["text"])
    return out or ["[1, 2, 3]"]


def send(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main():
    model = os.environ.get("FAKE_CODEX_MODEL", "gpt-6-astra")
    thread_model = os.environ.get("FAKE_CODEX_THREAD_MODEL", model)
    texts = texts_for(model)
    log = os.environ.get("FAKE_CODEX_LOG")
    forks = {}
    served = 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        msg = json.loads(line)
        if log:
            with open(log, "a") as f:
                f.write(line + "\n")
        method, rid, params = msg.get("method"), msg.get("id"), msg.get("params") or {}
        if method == "initialize":
            send({"id": rid, "result": {"userAgent": "fake-codex/0.0"}})
        elif method == "initialized":
            pass
        elif method == "thread/read":
            tid = params["threadId"]
            if tid.startswith("ephemeral-") or tid.startswith("side-"):
                send({"id": rid, "error": {"code": -32000, "message": f"no rollout found for thread {tid}"}})
            else:
                send({"id": rid, "result": {"thread": {"id": tid, "path": f"/tmp/fake/{tid}.jsonl", "ephemeral": False,
                                                       "model": thread_model, "modelProvider": "openai", "reasoningEffort": "high",
                                                       "cwd": "/tmp/fake-project", "name": "fake thread"}}})
        elif method == "thread/turns/list":
            send({"id": rid, "result": {"data": [{"id": "turn-last", "status": "completed"}], "nextCursor": None}})
        elif method == "thread/fork":
            fid = "ephemeral-" + uuid.uuid4().hex[:8]
            forks[fid] = params
            send({"id": rid, "result": {"thread": {"id": fid, "ephemeral": True, "forkedFromId": params["threadId"], "cwd": params.get("cwd"),
                                                   "model": params.get("model")},
                                        "model": params.get("model"), "modelProvider": params.get("modelProvider"),
                                        "reasoningEffort": (params.get("config") or {}).get("model_reasoning_effort"),
                                        "cwd": params.get("cwd"), "serviceTier": None}})
        elif method == "turn/start":
            fid = params["threadId"]
            turn_id = "turn-" + uuid.uuid4().hex[:6]
            send({"id": rid, "result": {"turn": {"id": turn_id, "status": "inProgress"}}})
            send({"method": "turn/started", "params": {"threadId": fid, "turn": {"id": turn_id, "status": "inProgress"}}})
            if os.environ.get("FAKE_CODEX_APPROVAL"):
                send({"id": 900 + served, "method": "item/commandExecution/requestApproval",
                      "params": {"threadId": fid, "turnId": turn_id, "command": "rm -rf /"}})
            if os.environ.get("FAKE_CODEX_TOOL"):
                send({"method": "item/started", "params": {"threadId": fid, "turnId": turn_id,
                                                           "item": {"id": "cmd-1", "type": "commandExecution", "command": "python3 -c 'import random'"}}})
            text = texts[served % len(texts)]
            served += 1
            send({"method": "item/started", "params": {"threadId": fid, "turnId": turn_id, "item": {"id": "msg-1", "type": "agentMessage", "text": ""}}})
            send({"method": "item/completed", "params": {"threadId": fid, "turnId": turn_id,
                                                         "item": {"id": "msg-1", "type": "agentMessage", "text": text, "phase": "final_answer"}}})
            send({"method": "thread/tokenUsage/updated", "params": {"threadId": fid, "turnId": turn_id,
                                                                    "tokenUsage": {"last": {"inputTokens": 12000, "cachedInputTokens": 11000, "outputTokens": 1300}}}})
            status = "failed" if os.environ.get("FAKE_CODEX_FAIL") else "completed"
            time.sleep(0.05)
            send({"method": "turn/completed", "params": {"threadId": fid, "turn": {"id": turn_id, "status": status}}})
        elif method == "turn/interrupt":
            send({"id": rid, "result": {}})
        elif rid is not None and method is None:
            pass  # reply to our own server request
        elif rid is not None:
            send({"id": rid, "error": {"code": -32601, "message": f"unsupported {method}"}})


if __name__ == "__main__":
    main()
