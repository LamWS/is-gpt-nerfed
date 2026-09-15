# Development notes

## Layout

| path | |
| --- | --- |
| `plugin/` | the Codex plugin: `.codex-plugin/plugin.json` (manifest + hooks), `skills/is-gpt-nerfed/` (SKILL.md, `scripts/nerfed`, `codex_appserver.py`, `modeltrace_core.py`, `vendor/`), `assets/` (ModelTrace bank + provenance, logo) |
| `.agents/plugins/marketplace.json` | makes the repository a local Codex marketplace |
| `macos/` | SwiftUI menu bar app (macOS 26). `build.sh --install` / `--run` / `--zip`; the plugin is copied into the bundle as a marketplace so the app can install itself |
| `bin/nerfed` | wrapper around `plugin/skills/is-gpt-nerfed/scripts/nerfed` |
| `tests/` | unit + offline end-to-end tests with a fake app-server (`fake_codex.py`); `test_parity.py` checks the scorer against ModelTrace's JS core (needs node) |
| `tools/set_icon.sh` | adopt a 1024×1024 PNG as app icon and plugin logo, rebuild |

`nerfed` is one Python 3.9+ script, standard library only, run by the system `python3`. Nothing is compiled except the app.

```bash
python3 -m unittest discover -s tests -v
./bin/nerfed selftest
./macos/build.sh --install          # Xcode 26
NERFED_DEMO=1 ~/Applications/IsGPTNerfed.app/Contents/MacOS/IsGPTNerfed --render docs/panel.png   # README images
```

## How Codex runs the plugin

- `codex plugin add` copies the plugin to `~/.codex/plugins/cache/is-gpt-nerfed/is-gpt-nerfed/<version>/` and exports
  `PLUGIN_ROOT` (that cache path) to hook commands. Hooks therefore run the cached copy: after changing code, run
  `./install.sh` again (or copy the changed files into the cache).
- Hook trust: Codex silently skips hooks it has not been told to trust. Trust is a per-definition hash under
  `[hooks.state."<hook key>"]` in `~/.codex/config.toml`, written through the app-server's `config/batchWrite`, the same
  call the Codex TUI's `/hooks` screen makes. `nerfed hooks status` / `nerfed hooks trust`. Any change to a hook command
  changes its hash and needs re-trusting; `install.sh` does that.
- A running Codex app keeps the hook definitions it loaded. Two rules keep reinstalls from hurting open threads:
  1. the hook entry point never exits non-zero (Codex reads a non-zero exit, and argparse's exit 2 in particular, as
     "block the user's turn"); the shell wrapper exits 0 when `python3` or the script is missing;
  2. `nerfed setup` leaves previous version paths resolvable (symlinks to the new copy) and maintains
     `~/.codex/is-gpt-nerfed/plugin` as a stable fallback path.
- The desktop app picked up a newly installed plugin and its trust within a few minutes without a restart in testing.
  The panel shows "Codex app has not loaded the plugin yet" / "still runs the previous version" while that is pending.

## Probes

- `codex_appserver.py` talks JSON-RPC to a private `codex app-server --stdio` (hooks and notifications disabled in that
  process): `thread/read`, `thread/turns/list`, `thread/fork` with `ephemeral: true` at the newest finished turn,
  `turn/start` per fork, collect the final agent message. Server-initiated requests (approvals) are refused.
- A thread whose newest turn is live cannot be forked at that turn (`identifies an in-progress turn`); the previous
  finished turn is used, else the probe waits up to `busy_wait_s` (600 s) and reports a retryable Invalid.
- One automatic retry on transport failures; a Suspicious first round triggers a second round (six answers).
- Verdict gate (`mismatch_confidence` 0.8): Mismatch needs p(top) ≥ 0.8, p(declared) ≤ 0.2 and a fused z-score margin
  ≥ 0.5σ, because ModelTrace's calibrated softmax amplifies small gaps.
- Fresh-session probe: `thread/start` with `ephemeral: true`, no history.

## Passive scanner

Reads the thread's rollout JSONL incrementally on every Stop hook. Findings and severities:

| finding | severity | trigger |
| --- | --- | --- |
| `silent_model_change` | hard | `turn_context.model` changed with no `thread_settings_applied` |
| `silent_effort_change` | hard | reasoning effort dropped with no settings change |
| `hidden_model` | hard | a model with `visibility=hide` in `models_cache.json` ran a turn |
| `context_window_change` | hard | `token_count.info.model_context_window` shrank |
| `applied_model_change` | soft | a lower-tier model was applied through thread settings ([openai/codex#28211](https://github.com/openai/codex/issues/28211)) |
| `service_tier_change` | info | priority tier dropped |

## Ledger (`~/.codex/is-gpt-nerfed/`)

| file | |
| --- | --- |
| `log.jsonl` | activity log, one JSON object per line: `account_switch`, `probe_due`, `worker_spawn`, `probe_start`, `probe_round` (per-fork model/effort/tier/timing/usage), `probe_wait`, `probe_retry`, `probe_confirm_round`, `probe_verdict` (candidate list), `scan_finding`, `hooks_trust`, `config_set`, `status_change`, `error`. `nerfed log --since 2h --kind probe_verdict --json` |
| `probes/*.json`, `probes.jsonl` | full probe records (every fork's answer text) and the index |
| `sessions/*.json` | per-thread schedule state, evidence, alerts |
| `events.jsonl` | raw hook event metadata |
| `account.json`, `hooks_status.json`, `state.json` | last seen account, cached hook trust state, last panel status |

The app also logs to the unified log (Console.app, subsystem `is-gpt-nerfed`).

## Full configuration

| key | default | |
| --- | --- | --- |
| `frequency` | `turns:8` | `turns:N`, `Nm`, `Nh` (of activity), `manual` |
| `fresh_frequency` | `manual` | `Nm`, `Nh`, `manual` |
| `mode` | `auto` | `auto` / `nudge` |
| `queries` | `3` | forks per probe, 1–3 |
| `parallel` | `true` | forks run concurrently |
| `languages` | `zh,en` | prompt language pool |
| `passive` | `true` | rollout scan on every turn |
| `notify`, `notify_on_ok` | `true`, `false` | macOS notifications |
| `announce_ok` | `false` | push Match verdicts into the thread |
| `sound` | `true` | Codex notification sound on a downgrade |
| `halt_on_mismatch` | `false` | deny work tools after a mismatch until `nerfed resume` |
| `mismatch_confidence` | `0.8` | verdict gate |
| `confirm_uncertain` | `true` | second round when Suspicious |
| `busy_wait_s` | `600` | how long to wait for a live turn |
| `hide_titles` | `false` | screenshot mode |
| `pet_name` | `Inspector Astra` | the persona's name |
| `codex_bin` | auto | path to the codex binary (found on PATH or inside the ChatGPT/Codex app) |

## Release

```bash
./macos/build.sh --zip                      # dist/IsGPTNerfed-<version>.zip + .sha256
gh release create v<version> dist/*.zip dist/*.sha256 --prerelease
```

The app is ad-hoc signed, not notarized: first launch needs right-click → Open. Codex also accepts the repository as a
git marketplace (`codex plugin marketplace add kiyoakii/is-gpt-nerfed`, `codex plugin add is-gpt-nerfed@is-gpt-nerfed`).

## Not verified yet

- The self-answer flow inside a real `/side` conversation (hooks firing there, the challenge/submit loop).
- Windows and Linux (the Python is portable; notifications and the app are macOS-only).
- Codex's app-server protocol is marked experimental; renames would break probing until `codex_appserver.py` is updated.
  `nerfed doctor --fork` proves the fork path against the installed Codex with zero inference.

Contributions welcome: detection signals, bank updates from upstream ModelTrace (keep `provenance.json` honest),
Windows/Linux, translations of Inspector Astra's lines. Keep the panel to its two type sizes and no icons.
