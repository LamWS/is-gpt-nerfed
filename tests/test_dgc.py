"""Unit + offline end-to-end tests for the dgc CLI. Run: python3 -m unittest discover -s tests -v"""
import importlib.machinery
import importlib.util
import io
import json
import os
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stdout
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = tempfile.mkdtemp(prefix="dgc-test-")
os.environ["NERFED_HOME"] = os.path.join(TMP, "ledger")
os.environ["CODEX_HOME"] = os.path.join(TMP, "codex-home")
os.makedirs(os.environ["CODEX_HOME"], exist_ok=True)
for var in ("CODEX_THREAD_ID", "CODEX_SESSION_ID", "CODEX_SANDBOX_NETWORK_DISABLED", "NERFED_PROBE_PROCESS"):
    os.environ.pop(var, None)

DGC_PATH = os.path.join(ROOT, "plugin", "skills", "is-gpt-nerfed", "scripts", "nerfed")
FAKE_CODEX = os.path.join(ROOT, "tests", "fake_codex.py")
loader = importlib.machinery.SourceFileLoader("dgc", DGC_PATH)
spec = importlib.util.spec_from_loader("dgc", loader)
dgc = importlib.util.module_from_spec(spec)
loader.exec_module(dgc)


def rollout_lines(*records):
    return "".join(json.dumps(r) + "\n" for r in records)


def turn(tid, model, effort):
    return {"type": "turn_context", "timestamp": f"t{tid}", "payload": {"turn_id": str(tid), "model": model,
            "collaboration_mode": {"settings": {"reasoning_effort": effort}}}}


def settings(model, effort, tier=None):
    s = {"model": model, "reasoning_effort": effort}
    if tier:
        s["service_tier"] = tier
    return {"type": "event_msg", "timestamp": "ts", "payload": {"type": "thread_settings_applied", "thread_settings": s}}


def tokens(ctx):
    return {"type": "event_msg", "payload": {"type": "token_count", "info": {"model_context_window": ctx}}}


def run_cli(argv, env=None):
    buf = io.StringIO()
    with mock.patch.dict(os.environ, env or {}):
        with redirect_stdout(buf):
            try:
                rc = dgc.main(argv)
            except SystemExit as e:
                rc = e.code
    return rc, buf.getvalue()


def run_hook(payload):
    with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), \
            mock.patch.object(sys.stdin, "isatty", return_value=False, create=True):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = dgc.main(["hook"])
    assert rc == 0
    return buf.getvalue()


def fixture_rows():
    with open(os.path.join(ROOT, "tests", "fixtures", "reference_subset.jsonl")) as f:
        return [json.loads(l) for l in f if l.strip()]


class ScannerTests(unittest.TestCase):
    def write(self, text):
        p = os.path.join(TMP, f"rollout-{os.urandom(3).hex()}.jsonl")
        with open(p, "w") as f:
            f.write(text)
        return p

    def test_silent_downgrade_is_hard_evidence(self):
        p = self.write(rollout_lines(turn(1, "gpt-6-astra", "max"), tokens(258400), turn(2, "gpt-reserve", "medium"), tokens(128000)))
        scan, ev = dgc.scan_full(p, frozenset({"gpt-reserve"}))
        sev = {e["kind"]: e["severity"] for e in ev}
        self.assertEqual(sev, {"silent_model_change": "hard", "silent_effort_change": "hard", "hidden_model": "hard", "context_window_change": "hard"})
        self.assertEqual(scan["models_seen"], {"gpt-6-astra": 1, "gpt-reserve": 1})

    def test_settings_applied_change_is_soft_or_info(self):
        p = self.write(rollout_lines(settings("gpt-6-astra", "max", "priority"), turn(1, "gpt-6-astra", "max"),
                                     settings("gpt-5.5", "high", "default"), turn(2, "gpt-5.5", "high"),
                                     settings("gpt-6-astra", "max", "default"), turn(3, "gpt-6-astra", "max")))
        _, ev = dgc.scan_full(p, frozenset())
        kinds = {(e["kind"], e["severity"]) for e in ev}
        self.assertIn(("applied_model_change", "soft"), kinds)
        self.assertIn(("applied_model_change", "info"), kinds)
        self.assertIn(("service_tier_change", "info"), kinds)
        self.assertFalse(any(k == "silent_model_change" for k, _ in kinds))

    def test_incremental_scan_and_partial_lines(self):
        p = self.write(rollout_lines(turn(1, "gpt-6-astra", "max")))
        scan = dgc.new_scan_state()
        self.assertEqual(dgc.scan_rollout(p, scan, frozenset()), [])
        with open(p, "a") as f:
            f.write('{"type": "turn_context", "payload": {"turn_id": "2", "model": "gpt-5.3-codex-spark"')
        self.assertEqual(dgc.scan_rollout(p, scan, frozenset()), [])
        with open(p, "a") as f:
            f.write("}}\n")
        ev = dgc.scan_rollout(p, scan, frozenset())
        self.assertEqual([(e["kind"], e["severity"]) for e in ev], [("silent_model_change", "hard")])
        self.assertEqual(dgc.scan_rollout(p, scan, frozenset()), [])


class LogicTests(unittest.TestCase):
    def test_ranking_and_frequency(self):
        self.assertGreater(dgc.model_rank("gpt-6-astra"), dgc.model_rank("gpt-5.6-sol"))
        self.assertEqual(dgc.classify_change("gpt-6-astra", "gpt-reserve"), "downgrade")
        self.assertEqual(dgc.classify_change("gpt-5.6-sol", "gpt-5.6-luna"), "lateral")
        self.assertEqual(dgc.parse_frequency("every 5 turns"), ("turns", 5))
        self.assertEqual(dgc.parse_frequency("2h"), ("minutes", 120))
        with self.assertRaises(ValueError):
            dgc.parse_frequency("sometimes")
        self.assertEqual(dgc.coerce_config_value("languages", "zh, en"), ["zh", "en"])
        with self.assertRaises(ValueError):
            dgc.coerce_config_value("languages", "klingon")

    @staticmethod
    def analysis(*rows):
        results = [{"model": m, "probability": p, "score": s} for m, p, s in rows]
        results.sort(key=lambda r: -r["probability"])
        return {"prediction": results[0]["model"], "probability": results[0]["probability"], "used_outputs": 3, "results": results}

    def test_verdicts(self):
        confident = self.analysis(("gpt-5.6-luna", 0.91, 1.8), ("gpt-6-astra", 0.03, 0.4), ("gpt-5.5", 0.06, 0.6))
        self.assertEqual(dgc.fingerprint_verdict("gpt-6-astra", confident, []), ("MISMATCH", "downgrade"))
        self.assertEqual(dgc.fingerprint_verdict("gpt-5.5", confident, []), ("MISMATCH", "upgrade"))
        self.assertEqual(dgc.fingerprint_verdict("openai/gpt-5.6-luna", confident, []), ("MATCH", None))
        self.assertEqual(dgc.fingerprint_verdict("gpt-7-nova", confident, []), ("UNLISTED", None))
        self.assertEqual(dgc.fingerprint_verdict(None, confident, []), ("UNKNOWN", None))
        self.assertEqual(dgc.fingerprint_verdict("gpt-6-astra", None, []), ("INVALID", None))
        self.assertEqual(dgc.fingerprint_verdict("gpt-6-astra", confident, [{"detail": "x"}]), ("DOWNGRADED!", "hard"))

    def test_confidence_gate(self):
        # top candidate wins but not confidently: SUSPICIOUS, never MISMATCH
        thin = self.analysis(("gpt-5.6-sol", 0.62, 1.1), ("gpt-6-astra", 0.31, 0.9), ("gpt-5.5", 0.07, 0.2))
        a = dgc.assess("gpt-6-astra", thin, [])
        self.assertEqual((a["verdict"], a["direction"], a["confidence"]), ("SUSPICIOUS", "downgrade", "low"))
        self.assertAlmostEqual(a["p_expected"], 0.31)
        self.assertAlmostEqual(a["margin"], 0.2)
        # a peaked softmax with a thin z-score margin is still SUSPICIOUS
        peaked = self.analysis(("gpt-5.6-sol", 0.95, 1.30), ("gpt-6-astra", 0.04, 1.05), ("gpt-5.5", 0.01, 0.1))
        self.assertEqual(dgc.assess("gpt-6-astra", peaked, [])["verdict"], "SUSPICIOUS")
        # p(top) high, p(declared) still too high
        split = self.analysis(("gpt-5.6-sol", 0.80, 1.5), ("gpt-6-astra", 0.20, 0.6), ("gpt-5.5", 0.0, 0.0))
        self.assertEqual(dgc.assess("gpt-6-astra", split, [])["verdict"], "MISMATCH")
        self.assertEqual(dgc.assess("gpt-6-astra", split, [], {"mismatch_confidence": 0.9})["verdict"], "SUSPICIOUS")
        # a weak MATCH is still a MATCH, flagged low confidence
        weak = self.analysis(("gpt-6-astra", 0.55, 1.0), ("gpt-5.6-sol", 0.45, 0.9))
        a = dgc.assess("gpt-6-astra", weak, [])
        self.assertEqual((a["verdict"], a["confidence"]), ("MATCH", "low"))
        self.assertFalse(dgc.needs_confirmation("gpt-6-astra", [], {"confirm_uncertain": True}))

    def test_probe_due(self):
        st = dgc.new_session("s")
        st["kind"], st["turns"] = "main", 7
        cfg = {"frequency": "turns:8", "nudge_cooldown_turns": 4}
        self.assertFalse(dgc.probe_due(st, cfg))
        st["turns"] = 8
        self.assertTrue(dgc.probe_due(st, cfg))
        st["last_probe_turn"] = 8
        self.assertFalse(dgc.probe_due(st, cfg))
        self.assertFalse(dgc.probe_due(st, {"frequency": "manual"}))
        st["created_ts"] = dgc.now() - 3600
        self.assertTrue(dgc.probe_due(st, {"frequency": "30m"}))


class ForkProbeTests(unittest.TestCase):
    """Drive the real probe runner against the fake app-server."""

    def setUp(self):
        dgc.ensure_dirs()
        dgc.save_config({**dgc.DEFAULT_CONFIG, "codex_bin": FAKE_CODEX, "notify": False, "sound": False, "probe_timeout_s": 30})
        dgc._BANK = None

    def test_match(self):
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "main-thread-1"], {"FAKE_CODEX_MODEL": "gpt-6-astra"})
        self.assertEqual(rc, 0, out)
        self.assertIn("verdict: MATCH", out)
        self.assertIn("3/3 answers used", out)
        rec = dgc.read_json(dgc.probe_path(out.split("probe ")[1].split()[0]))
        self.assertEqual(rec["expected"], "gpt-6-astra")
        self.assertEqual(rec["prediction"], "gpt-6-astra")
        self.assertEqual(len(rec["forks"]), 3)
        self.assertTrue(all(f["usage"]["cached"] == 11000 for f in rec["forks"]))
        st = dgc.load_session("main-thread-1")
        self.assertEqual(st["alerts"], [], "MATCH is silent in the thread by default")
        self.assertIsNone(st["probe_running"])

    def test_mismatch_is_a_downgrade_with_alert_and_optional_halt(self):
        dgc.save_config({**dgc.load_config(), "halt_on_mismatch": True})
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "main-thread-2"], {"FAKE_CODEX_MODEL": "gpt-5.5", "FAKE_CODEX_THREAD_MODEL": "gpt-6-astra"})
        self.assertEqual(rc, 0, out)
        self.assertIn("verdict: MISMATCH", out)
        self.assertIn("direction: downgrade", out)
        st = dgc.load_session("main-thread-2")
        self.assertEqual(len(st["alerts"]), 1)
        self.assertIsNotNone(st["halt"])
        # the halt denies work tools but lets dgc commands through; resume clears it
        base = {"session_id": "main-thread-2", "cwd": TMP, "model": "gpt-6-astra"}
        denied = json.loads(run_hook({**base, "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "npm test"}}))
        self.assertEqual(denied["decision"], "deny")
        self.assertEqual(denied["hookSpecificOutput"]["permissionDecision"], "deny")
        # the alert is handed to the model on the next model-visible hook, exactly once
        out = json.loads(run_hook({**base, "hook_event_name": "UserPromptSubmit", "prompt": "hi"}))
        self.assertIn("tell the user", out["hookSpecificOutput"]["additionalContext"].lower())
        self.assertIn("Congrats", out["systemMessage"])
        self.assertEqual(run_hook({**base, "hook_event_name": "UserPromptSubmit", "prompt": "again"}).strip(), "")
        # dgc's own commands pass through the halt; resume clears it
        allowed = run_hook({**base, "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": f"{DGC_PATH} resume --thread main-thread-2"}})
        self.assertNotIn('"deny"', allowed)
        run_cli(["resume", "--thread", "main-thread-2"])
        self.assertIsNone(dgc.load_session("main-thread-2")["halt"])

    def test_tool_attempt_and_failed_turn_are_invalid(self):
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "main-thread-3"], {"FAKE_CODEX_TOOL": "1"})
        self.assertIn("verdict: INVALID", out)
        self.assertIn("attempted a tool", out)
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "main-thread-3"], {"FAKE_CODEX_FAIL": "1"})
        self.assertIn("verdict: INVALID", out)
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "main-thread-3"], {"FAKE_CODEX_APPROVAL": "1"})
        self.assertIn("verdict: INVALID", out)
        self.assertIn("refused", out)

    def test_transport_failure_is_retried_once(self):
        marker = os.path.join(TMP, "fail-once")
        open(marker, "w").close()
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "main-thread-9"],
                          {"FAKE_CODEX_MODEL": "gpt-6-astra", "FAKE_CODEX_FAIL_ONCE": marker})
        self.assertIn("verdict: MATCH", out)
        self.assertIn("retried ×1", out)
        self.assertFalse(os.path.exists(marker))
        rec = dgc.read_json(dgc.probe_path(out.split("probe ")[1].split()[0]))
        self.assertEqual(rec["retries"], 1)
        self.assertEqual(rec["rounds"], 1)

    def test_suspicious_first_round_gets_a_confirmation_round(self):
        calls = {"n": 0}
        real = dgc.needs_confirmation

        def once(expected, outputs, cfg):
            calls["n"] += 1
            return calls["n"] == 1 or real(expected, outputs, cfg)

        with mock.patch.object(dgc, "needs_confirmation", side_effect=once):
            rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "main-thread-10"], {"FAKE_CODEX_MODEL": "gpt-6-astra"})
        self.assertIn("6/6 answers used in 2 rounds", out)
        rec = dgc.read_json(dgc.probe_path(out.split("probe ")[1].split()[0]))
        self.assertEqual(rec["rounds"], 2)
        self.assertEqual(len(rec["forks"]), 6)
        self.assertEqual(rec["verdict"], "MATCH")

    def test_live_turn_falls_back_to_previous_finished_turn(self):
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "busy-thread-1"],
                          {"FAKE_CODEX_MODEL": "gpt-6-astra", "FAKE_CODEX_BUSY_MODE": "fallback"})
        self.assertIn("verdict: MATCH", out)
        rec = dgc.read_json(dgc.probe_path(out.split("probe ")[1].split()[0]))
        self.assertEqual(rec["thread"]["last_turn"], "turn-prev")
        self.assertFalse(rec.get("waited_for_turn"))

    def test_live_turn_is_waited_for(self):
        import threading
        marker = os.path.join(TMP, "busy-until")
        open(marker, "w").close()
        dgc.save_config({**dgc.load_config(), "busy_wait_s": 30})
        threading.Timer(2.5, lambda: os.remove(marker)).start()
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "busy-thread-2"],
                          {"FAKE_CODEX_MODEL": "gpt-6-astra", "FAKE_CODEX_BUSY_MODE": "wait", "FAKE_CODEX_BUSY_UNTIL": marker})
        self.assertIn("verdict: MATCH", out)
        rec = dgc.read_json(dgc.probe_path(out.split("probe ")[1].split()[0]))
        self.assertTrue(rec.get("waited_for_turn"))
        self.assertEqual(rec["thread"]["last_turn"], "turn-only")
        rc, log = run_cli(["log", "--probe", rec["id"], "--json"])
        kinds = [json.loads(l)["kind"] for l in log.splitlines() if l.strip()]
        self.assertEqual(kinds[0], "probe_start")
        self.assertIn("probe_wait", kinds)
        self.assertIn("probe_round", kinds)
        self.assertEqual(kinds[-1], "probe_verdict")
        dgc.save_config({**dgc.load_config(), "busy_wait_s": 600})

    def test_live_turn_gives_up_after_busy_wait(self):
        marker = os.path.join(TMP, "busy-forever")
        open(marker, "w").close()
        dgc.save_config({**dgc.load_config(), "busy_wait_s": 1})
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "busy-thread-3"],
                          {"FAKE_CODEX_MODEL": "gpt-6-astra", "FAKE_CODEX_BUSY_MODE": "wait", "FAKE_CODEX_BUSY_UNTIL": marker})
        self.assertIn("verdict: INVALID", out)
        self.assertIn("stayed busy", out)
        snap = json.loads(run_cli(["snapshot", "--json"])[1])
        p = next(p for p in snap["recent_probes"] if p["thread_id"] == "busy-thread-3")
        self.assertTrue(p["retryable"], "a busy thread must offer Retry in the panel")
        os.remove(marker)
        dgc.save_config({**dgc.load_config(), "busy_wait_s": 600})

    def test_hooks_status_and_trust(self):
        trust_file = os.path.join(TMP, "trusted-hooks.json")
        env = {"FAKE_CODEX_TRUST_FILE": trust_file}
        rc, out = run_cli(["hooks", "status"], env)
        self.assertEqual(rc, 1)
        self.assertIn("0/5 hooks trusted", out)
        rc, out = run_cli(["hooks", "trust"], env)
        self.assertEqual(rc, 0)
        self.assertIn("trusted 5 hook(s)", out)
        self.assertIn("5/5 hooks trusted", out)
        self.assertEqual(len(json.load(open(trust_file))), 5)
        snap = json.loads(run_cli(["snapshot", "--json"], env)[1])
        self.assertEqual(snap["hooks"]["state"], "trusted")
        self.assertEqual(snap["hooks"]["trusted"], 5)
        rc, out = run_cli(["log", "--kind", "hooks_trust"])
        self.assertIn("hooks_trust", out)
        os.remove(dgc.HOOKS_STATUS_PATH)

    def test_unlisted_expected_model(self):
        rc, out = run_cli(["probe", "now", "--mode", "fork", "--thread", "main-thread-4"], {"FAKE_CODEX_MODEL": "gpt-6-astra", "FAKE_CODEX_THREAD_MODEL": "gpt-7-nova"})
        self.assertIn("verdict: UNLISTED", out)

    def test_sandbox_queues_and_stop_hook_spawns_worker(self):
        dgc.save_config({**dgc.load_config(), "frequency": "manual"})
        with mock.patch.object(dgc, "thread_is_persisted", return_value=True):
            rc, out = run_cli(["probe", "now"], {"CODEX_THREAD_ID": "main-thread-5", "CODEX_SANDBOX_NETWORK_DISABLED": "1"})
        self.assertIn("Queued", out)
        self.assertTrue(dgc.load_session("main-thread-5")["requested"])
        # a Stop hook in that (main) thread launches the background worker, which uses the fake codex
        with mock.patch.object(dgc, "link_session", side_effect=lambda st: st.update(kind="main")), \
                mock.patch.dict(os.environ, {"FAKE_CODEX_MODEL": "gpt-5.6-luna", "FAKE_CODEX_THREAD_MODEL": "gpt-6-astra"}):
            run_hook({"session_id": "main-thread-5", "cwd": TMP, "model": "gpt-6-astra", "hook_event_name": "Stop"})
        deadline = time.time() + 30
        while time.time() < deadline:
            rows = [r for r in dgc.iter_jsonl(dgc.PROBES_INDEX) if r.get("thread_id") == "main-thread-5"]
            if rows:
                break
            time.sleep(0.3)
        self.assertTrue(rows, "worker did not record a probe")
        self.assertEqual(rows[-1]["verdict"], "MISMATCH")
        st = dgc.load_session("main-thread-5")
        self.assertFalse(st["requested"])
        self.assertIsNone(st["probe_running"])
        self.assertEqual(len(st["alerts"]), 1)

    def test_scheduler_spawns_when_due(self):
        dgc.save_config({**dgc.load_config(), "frequency": "turns:2", "mode": "auto"})
        base = {"session_id": "main-thread-6", "cwd": TMP, "model": "gpt-6-astra"}
        with mock.patch.object(dgc, "link_session", side_effect=lambda st: st.update(kind="main")), \
                mock.patch.object(dgc, "spawn_worker", return_value=True) as spawn:
            run_hook({**base, "hook_event_name": "UserPromptSubmit", "prompt": "1"})
            run_hook({**base, "hook_event_name": "Stop"})
            spawn.assert_not_called()
            run_hook({**base, "hook_event_name": "UserPromptSubmit", "prompt": "2"})
            run_hook({**base, "hook_event_name": "Stop"})
            spawn.assert_called_once()
            run_hook({**base, "hook_event_name": "UserPromptSubmit", "prompt": "3"})
            run_hook({**base, "hook_event_name": "Stop"})
            spawn.assert_called_once()  # a probe is marked running; no double launch
        dgc.save_config({**dgc.load_config(), "mode": "nudge"})
        st = dgc.load_session("main-thread-6")
        st["probe_running"], st["turns"], st["last_probe_turn"] = None, 10, 0
        dgc.save_session(st)
        with mock.patch.object(dgc, "link_session", side_effect=lambda st: st.update(kind="main")):
            out = json.loads(run_hook({**base, "hook_event_name": "Stop"}))
        self.assertIn("$is-gpt-nerfed", out["systemMessage"])

    def test_self_answer_mode_inside_side_conversation(self):
        rows = fixture_rows()
        astra = [r for r in rows if r["model_id"] == "gpt-6-astra"]
        with mock.patch.object(dgc, "thread_is_persisted", return_value=False), \
                mock.patch.object(dgc, "db_recent_main_thread", return_value={"id": "main-thread-7", "model": "gpt-6-astra"}), \
                mock.patch.object(dgc, "db_thread", side_effect=lambda t: {"id": "main-thread-7", "model": "gpt-6-astra"} if t == "main-thread-7" else None):
            rc, out = run_cli(["probe", "now"], {"CODEX_THREAD_ID": "side-ephemeral-1"})
            self.assertIn("challenge 1/3", out)
            pid = out.split("DGC PROBE ")[1].split()[0]
            rc, out = run_cli(["probe", "submit-numbers", pid, "--numbers", astra[0]["text"]])
            self.assertIn("challenge 2/3", out)
            rc, out = run_cli(["probe", "submit-numbers", pid, "--numbers", "[1, 2, 3]"])
            self.assertIn("will not count", out)
            self.assertIn("challenge 3/3", out)
            rc, out = run_cli(["probe", "submit-numbers", pid, "--numbers", astra[1]["text"]])
        self.assertIn("verdict: MATCH", out)
        self.assertIn("2/3 answers used", out)
        rec = dgc.read_json(dgc.probe_path(pid))
        self.assertEqual(rec["mode"], "self")
        self.assertEqual(rec["thread_id"], "main-thread-7")
        self.assertEqual(rec["side_thread_id"], "side-ephemeral-1")

    def test_report_and_explain(self):
        run_cli(["probe", "now", "--mode", "fork", "--thread", "main-thread-8"], {"FAKE_CODEX_MODEL": "gpt-5.4", "FAKE_CODEX_THREAD_MODEL": "gpt-5.4"})
        pid = [r for r in dgc.iter_jsonl(dgc.PROBES_INDEX) if r["thread_id"] == "main-thread-8"][-1]["id"]
        rc, out = run_cli(["report"])
        self.assertIn(pid, out)
        self.assertIn("MATCH", out)
        rc, out = run_cli(["explain", pid])
        self.assertIn("attribution:", out)
        self.assertIn("gpt-5.4", out)
        rc, out = run_cli(["explain", "--method"])
        self.assertIn("ModelTrace", out)
        rc, out = run_cli(["status"])
        self.assertEqual(rc, 0)

    def test_records_follow_the_signed_in_account(self):
        auth = os.path.join(os.environ["CODEX_HOME"], "auth.json")

        def sign_in(account_id):
            with open(auth, "w") as f:
                json.dump({"auth_mode": "chatgpt", "tokens": {"account_id": account_id}}, f)

        sign_in("account-A")
        a = dgc.current_account()
        self.assertNotIn("account-A", json.dumps(a), "raw account id must never be stored")
        dgc.save_config({**dgc.load_config(), "frequency": "turns:8"})
        base = {"session_id": "acct-thread-A", "cwd": TMP, "model": "gpt-6-astra"}
        with mock.patch.object(dgc, "link_session", side_effect=lambda st: st.update(kind="main")):
            run_hook({**base, "hook_event_name": "UserPromptSubmit", "prompt": "1"})
        run_cli(["probe", "now", "--mode", "fork", "--thread", "acct-thread-A"], {"FAKE_CODEX_MODEL": "gpt-6-astra"})
        rec = [r for r in dgc.iter_jsonl(dgc.PROBES_INDEX) if r["thread_id"] == "acct-thread-A"][-1]
        self.assertEqual(rec["account_id"], a["id"])
        snap = json.loads(run_cli(["snapshot", "--json"])[1])
        t = next(t for t in snap["threads"] if t["id"] == "acct-thread-A")
        self.assertFalse(t["unverified"])
        self.assertFalse(t["last_probe"]["stale_account"])
        self.assertFalse(t["due"], "just probed under this account")
        # switch accounts: the thread stays (threads are shared), but its verdict no longer vouches for this account
        sign_in("account-B")
        snap = json.loads(run_cli(["snapshot", "--json"])[1])
        t = next(t for t in snap["threads"] if t["id"] == "acct-thread-A")
        self.assertTrue(t["unverified"])
        self.assertTrue(t["last_probe"]["stale_account"])
        self.assertTrue(t["due"], "must be re-probed under the new account")
        self.assertIn("unverified", snap["overall"]["message"])
        self.assertGreaterEqual(snap["overall"]["unverified"], 1)
        self.assertEqual(snap["overall"]["status"], "unverified")
        with mock.patch.object(dgc, "link_session", side_effect=lambda st: st.update(kind="main")), \
                mock.patch.object(dgc, "spawn_worker", return_value=True) as spawn:
            run_hook({**base, "hook_event_name": "Stop"})
            spawn.assert_called_once()
        rc, out = run_cli(["report"])
        self.assertIn("another Codex account", out)
        os.remove(auth)

    def test_pre_tracking_records_are_unknown_and_unverified(self):
        # a record from before accounts were tracked, tagged by the buggy v1 migration (label "", plan None)
        dgc.ensure_dirs()
        rec = {"id": "legacy0001", "mode": "fresh", "thread_id": None, "status": "done", "verdict": "MATCH", "expected": "gpt-6-astra",
               "prediction": "gpt-6-astra", "probability": 1.0, "finished": dgc.iso(), "account": {"id": "deadbeef1234", "label": "", "plan": None}}
        dgc.write_json(dgc.probe_path("legacy0001"), rec)
        dgc.append_jsonl(dgc.PROBES_INDEX, {"id": "legacy0001", "mode": "fresh", "thread_id": None, "status": "done", "verdict": "MATCH",
                                             "expected": "gpt-6-astra", "prediction": "gpt-6-astra", "probability": 1.0,
                                             "finished": dgc.iso(), "account_id": "deadbeef1234"})
        with open(os.path.join(dgc.NERFED_HOME, ".accounts-migrated"), "w") as f:
            f.write("2026-09-15T07:22:34Z\n")  # v1 marker
        snap = json.loads(run_cli(["snapshot", "--json"])[1])
        legacy = next(p for p in snap["recent_probes"] if p["id"] == "legacy0001")
        self.assertEqual(legacy["account_state"], "unknown")
        self.assertTrue(legacy["stale_account"])
        self.assertNotEqual(snap["overall"]["status"], "ok")
        self.assertIn("unverified", snap["overall"]["message"])
        migrated = dgc.read_json(dgc.probe_path("legacy0001"))
        self.assertEqual(migrated["account"]["id"], "unknown")
        with open(os.path.join(dgc.NERFED_HOME, ".accounts-migrated")) as f:
            self.assertTrue(f.read().startswith("v2"))
        rc, out = run_cli(["log", "--kind", "migration", "--json"])
        self.assertIn('"records_marked_unknown": 1', out)

    def test_account_switch_is_logged_and_shown(self):
        auth = os.path.join(os.environ["CODEX_HOME"], "auth.json")
        with open(auth, "w") as f:
            json.dump({"auth_mode": "chatgpt", "tokens": {"account_id": "switch-A"}}, f)
        snap_a = json.loads(run_cli(["snapshot", "--json"])[1])
        with open(auth, "w") as f:
            json.dump({"auth_mode": "chatgpt", "tokens": {"account_id": "switch-B"}}, f)
        snap_b = json.loads(run_cli(["snapshot", "--json"])[1])
        self.assertIsNotNone(snap_b["account"]["switched_ago"])
        self.assertIsNone(snap_a["account"].get("switched_ago") if snap_a["account"].get("switched_at") is None else None)
        rc, out = run_cli(["log", "--kind", "account_switch", "--json"])
        rows = [json.loads(l) for l in out.splitlines() if l.strip()]
        self.assertTrue(rows)
        last = rows[-1]
        self.assertNotIn("switch-A", json.dumps(last))
        self.assertEqual(len(last["from_id"]), 12)
        self.assertNotEqual(last["from_id"], last["to_id"])
        os.remove(auth)

    def test_hook_never_crashes(self):
        with mock.patch.object(sys, "stdin", io.StringIO("this is not json")), \
                mock.patch.object(sys.stdin, "isatty", return_value=False, create=True):
            self.assertEqual(dgc.main(["hook"]), 0)


if __name__ == "__main__":
    unittest.main()
