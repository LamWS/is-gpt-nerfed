"""Served-model detection via the Responses API's own metadata.

When Codex talks to its backend (chatgpt.com/backend-api/codex/responses), the server
puts the model that ACTUALLY served the request into the SSE stream: the very first
event, `response.created`, carries `response.model` — which can differ from the model
the client asked for. The response headers advertise the capacity-fallback policy
behind such swaps:

    x-codex-safety-buffering-enabled: true
    x-codex-safety-buffering-faster-model: gpt-5.6-luna

One tiny streaming request (closed right after the first event, before any tokens are
generated) therefore answers "who would actually serve this account right now" with
authority — no fingerprint statistics, no 300-number challenges, and it works for
models that are not in the fingerprint bank at all.

The check never touches the refresh token in auth.json: OpenAI rotates refresh tokens
on use, and a plugin that consumed one without persisting the replacement would break
the user's Codex login. An expired access token simply skips the check and the caller
falls back to the fingerprint probe.
"""
from __future__ import annotations

import base64
import json
import os
import time
import urllib.error
import urllib.request

RESPONSES_URL = os.environ.get("NERFED_RESPONSES_URL") or "https://chatgpt.com/backend-api/codex/responses"


def _jwt_payload(token: str) -> dict:
    try:
        part = token.split(".")[1]
        part += "=" * (-len(part) % 4)
        return json.loads(base64.urlsafe_b64decode(part))
    except Exception:
        return {}


def read_access_token(codex_home: str, skew_s: float = 60) -> str | None:
    """The ChatGPT-login access token from Codex's auth.json, only while its JWT exp is valid."""
    try:
        with open(os.path.join(codex_home, "auth.json")) as f:
            d = json.load(f)
    except Exception:
        return None
    tok = (d.get("tokens") or {}).get("access_token")
    if not isinstance(tok, str) or tok.count(".") != 2:
        return None
    if float(_jwt_payload(tok).get("exp") or 0) - time.time() < skew_s:
        return None
    return tok


def check_served_model(model: str, codex_home: str, timeout_s: float = 30, originator: str = "codex_cli_rs") -> dict:
    """Ask the backend who would serve `model` for the signed-in account right now.

    Returns {"ok", "requested", "served", "buffering_enabled", "buffering_faster_model",
             "plan", "request_id", "error"}.
    `served` is the model from the response's own metadata; it equals `requested` when
    no fallback happened. The connection is closed after `response.created`, so the
    check costs no generated tokens. `originator` identifies the client the check runs
    as, in case routing depends on it (the forks do the same).
    """
    out = {"ok": False, "requested": model, "served": None, "buffering_enabled": None,
           "buffering_faster_model": None, "plan": None, "request_id": None, "error": None}
    token = read_access_token(codex_home)
    if not token:
        out["error"] = "no valid access token (missing or expired)"
        return out
    body = json.dumps({
        "model": model,
        "instructions": "You are Codex.",
        "input": [{"type": "message", "role": "user",
                   "content": [{"type": "input_text", "text": "say ok"}]}],
        "store": False,
        "stream": True,
    }).encode()
    req = urllib.request.Request(RESPONSES_URL, data=body, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "OpenAI-Beta": "responses=v1",
        "originator": originator,
        "Accept": "text/event-stream",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            h = resp.headers
            out["buffering_enabled"] = h.get("x-codex-safety-buffering-enabled")
            out["buffering_faster_model"] = h.get("x-codex-safety-buffering-faster-model")
            out["plan"] = h.get("x-codex-plan-type")
            out["request_id"] = h.get("x-oai-request-id")
            deadline = time.time() + timeout_s
            while time.time() < deadline:
                line = resp.readline()
                if not line:
                    break
                line = line.strip()
                if not line.startswith(b"data:"):
                    continue
                try:
                    ev = json.loads(line[5:].strip())
                except Exception:
                    continue
                if ev.get("type") == "response.created":
                    served = (ev.get("response") or {}).get("model")
                    if served:
                        out.update(ok=True, served=served)
                    break
            if not out["ok"] and not out["error"]:
                out["error"] = "stream ended before response.created"
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = e.read(200).decode("utf-8", "replace")
        except Exception:
            pass
        out["error"] = f"HTTP {e.code}: {detail}"
    except Exception as e:
        out["error"] = f"{type(e).__name__}: {e}"
    return out
