# Development notes

## Layout

| path | |
| --- | --- |
| `plugin/` | the Codex plugin: `.codex-plugin/plugin.json` (manifest + hooks), `skills/is-gpt-nerfed/` (SKILL.md, `scripts/nerfed`, `codex_appserver.py`, `modeltrace_core.py`, `vendor/`), `assets/` (ModelTrace bank + provenance, logo) |
| `.agents/plugins/marketplace.json` | makes the repository a local Codex marketplace |
| `macos/` | SwiftUI menu bar app (macOS 26). `build.sh --install` / `--run` / `--zip` / `--dmg` / `--release`; the plugin is copied into the bundle so the app can install itself |
| `bin/nerfed`, `install.sh`, `uninstall.sh` | the CLI wrapper and the plugin-only install |
| `install-app.sh` | one-line install of the latest release (curl, checksum, no quarantine flag) |
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
  `PLUGIN_ROOT` (that path) to hook commands, so hooks run the cached copy. After changing code, copy the changed
  files into the cache or run `./install.sh`. When the manifest version changes, Codex Desktop re-caches on its own and
  drops the old version directory; `~/.codex/is-gpt-nerfed/plugin` is kept as a stable fallback path for the hooks.
- Hook trust: Codex silently skips hooks it has not been told to trust. Trust is a per-definition hash under
  `[hooks.state."<hook key>"]` in `~/.codex/config.toml`, written through the app-server's `config/batchWrite`, the same
  call the Codex TUI's `/hooks` screen makes (`nerfed hooks status` / `nerfed hooks trust`). The hash covers the hook
  command, so changing a command needs re-trusting; `install.sh` does that.
- A non-zero exit from a hook (argparse's exit 2 included) makes Codex block the user's turn. The hook entry point
  therefore never exits non-zero, and the shell wrapper exits 0 when `python3` or the script is missing.
  `~/.codex/is-gpt-nerfed/errors.log` is where a crashed hook leaves its trace.

## Probes

- `codex_appserver.py` talks JSON-RPC to a private `codex app-server --stdio` (hooks and notifications disabled in that
  process): `thread/read`, `thread/turns/list`, `thread/fork` with `ephemeral: true` at the newest finished turn,
  `turn/start` per fork, collect the final agent message. Server-initiated requests (approvals) are refused.
- A session whose newest turn is live cannot be forked at that turn (`identifies an in-progress turn`); the previous
  finished turn is used, else the probe waits up to `busy_wait_s` (600 s) and reports a retryable Invalid.
- One automatic retry on transport failures. A Suspicious verdict stands until the next probe; `confirm_uncertain` (off
  by default) adds one more round of three answers.
- Verdict gate (`mismatch_confidence` 0.8): Mismatch needs p(top) ≥ 0.8, p(declared) ≤ 0.2 and a fused z-score margin
  ≥ 0.5σ, because ModelTrace's calibrated softmax amplifies small gaps.
- Fresh-session probe: `thread/start` with `ephemeral: true`, no history.
- The zh and en prompts are ModelTrace's own texts, verbatim. Its bank was enrolled under twelve unnamed conditions and
  its author calls other languages uncalibrated, so the prompt language is not a user setting (`languages` stays as a
  config key).

## Passive scanner

Reads the session's rollout JSONL incrementally on every Stop hook.

| finding | severity | trigger |
| --- | --- | --- |
| `silent_model_change` | hard / good | `turn_context.model` changed with no `thread_settings_applied`: hard for a downgrade, good for a confident upgrade, soft otherwise |
| `applied_model_change` | soft / good | the same change applied through thread settings: soft for a downgrade ("was that you?"), good for an upgrade |
| `silent_effort_change`, `applied_effort_change` | hard / soft | reasoning effort dropped, silently or through settings |
| `hidden_model` | hard | a model with `visibility=hide` in `models_cache.json` ran a turn |
| `context_window_change` | hard | `token_count.info.model_context_window` shrank |
| `service_tier_change` | info | priority tier dropped |

Only the latest change per dimension (model, effort, context window, tier) is active; a reverted change stays in the
log and the report. Better or worse (`compare_models`) is not a list of names. In order of trust: the catalog's
successor pointer (`upgrade` in `models_cache.json`), hidden internal models, the generation in the slug (gpt-5.6 →
gpt-6, claude-opus-4-7 → 4-8), the size tier in the slug (nano, mini/spark/lite/small/flash, plain, pro/ultra), then
the catalog's ranking (`priority`), the highest supported reasoning effort and the context window. Each answer carries
a confidence; only high or medium upgrades become good news.

`token_count.rate_limits` is not the bucket a turn was charged to and says nothing about the model that answered:
Codex parses one snapshot per limit family from the response headers in alphabetical order (`codex`, then e.g.
`codex_bengalfox`, the GPT-5.3-Codex-Spark allowance) and persists the last one. The server's `x-codex-active-limit`
header is the real bucket, and no header names the serving model, so the fingerprint stays the only measurement. The
scanner reads `rate_limits` only for the "at the usage limit" label, and only from the unnamed default family.

## Ledger (`~/.codex/is-gpt-nerfed/`)

| file | |
| --- | --- |
| `log.jsonl` | activity log, one JSON object per line: `account_switch`, `probe_due`, `worker_spawn`, `probe_start`, `probe_round` (per-fork model/effort/tier/timing/usage), `probe_wait`, `probe_retry`, `probe_verdict` (candidate list), `scan_finding`, `hooks_trust`, `config_set`, `status_change`, `update_check`, `error`. `nerfed log --since 2h --kind probe_verdict --json` |
| `probes/*.json`, `probes.jsonl` | full probe records (every fork's answer text) and the index |
| `sessions/*.json` | per-session schedule state, evidence, alerts |
| `events.jsonl` | raw hook event metadata |
| `account.json`, `hooks_status.json`, `state.json`, `update.json` | last seen account, cached hook trust, last panel status, last release check |

The app also logs to the unified log (Console.app, subsystem `is-gpt-nerfed`).

## Full configuration

| key | default | |
| --- | --- | --- |
| `frequency` | `30m` | `Nm`, `Nh` (of activity), `turns:N`, `manual` |
| `fresh_frequency` | `manual` | `Nm`, `Nh`, `manual` |
| `mode` | `auto` | `auto` / `nudge` |
| `queries` | `3` | forks per probe, 1–3 |
| `parallel` | `true` | forks run concurrently |
| `languages` | `zh,en` | prompt language pool (ModelTrace's texts) |
| `passive` | `true` | rollout scan on every turn |
| `notify`, `notify_on_ok` | `true`, `false` | macOS notifications |
| `announce_ok` | `false` | push Match verdicts into the session |
| `sound` | `true` | Codex notification sound on a downgrade |
| `halt_on_mismatch` | `false` | deny work tools after a mismatch until `nerfed resume` |
| `mismatch_confidence` | `0.8` | verdict gate |
| `confirm_uncertain` | `false` | second round when Suspicious |
| `busy_wait_s` | `600` | how long to wait for a live turn |
| `hide_titles` | `false` | screenshot mode |
| `check_updates` | `true` | ask GitHub for a newer release every 10 minutes |
| `codex_bin` | auto | path to the codex binary (found on PATH or inside the ChatGPT/Codex app) |

## Release

```bash
./macos/build.sh --zip && ./macos/build.sh --dmg        # dist/IsGPTNerfed-<version>.{zip,dmg} + .sha256
gh release create v<version> dist/IsGPTNerfed-<version>.* --title <version>
```

Tag `vX.Y.Z`, not a pre-release: `releases/latest` is what the app and `install-app.sh` read. The app checks every
10 minutes (`nerfed update-check`, state in `update.json`) and shows "vX.Y.Z is out · update" in the footer, one
notification per version. Clicking it runs `nerfed update-install` detached: download the zip, verify its sha256, stop
the app, move the old bundle to the Trash, put the new one in place, strip quarantine, relaunch. A failed check is
silent; a failed install shows "Update failed · retry". Codex also accepts the repository as a git marketplace
(`codex plugin marketplace add kiyoakii/is-gpt-nerfed`, `codex plugin add is-gpt-nerfed@is-gpt-nerfed`).

### Signing and notarization

Not done yet (needs an Apple Developer Program membership; an individual's certificate carries their legal name). Until
then the app is ad-hoc signed: `install-app.sh` and the self-updater avoid the Gatekeeper block, a browser download
needs System Settings → Privacy & Security → Open Anyway. When a Developer ID exists:

1. Xcode → Settings → Accounts → Manage Certificates → + → **Developer ID Application**;
   `security find-identity -v -p codesigning` then lists it.
2. `xcrun notarytool store-credentials nerfed-notary --apple-id <email> --team-id <TEAMID> --password <app-specific password>`.
3. `SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=nerfed-notary ./macos/build.sh --release`
   signs (hardened runtime, timestamp), notarizes and staples the zip and the dmg; `spctl -a -vv` must end with
   `source=Notarized Developer ID`.

## Limits and contributions

Windows and Linux are untested (the Python is portable; notifications and the app are macOS-only). Codex's app-server
protocol is marked experimental; `nerfed doctor --fork` proves the fork path against the installed Codex with zero
inference. Welcome: detection signals, bank updates from upstream ModelTrace (keep `provenance.json` honest),
Windows/Linux. Keep the panel to its type scale (17 / 13 / 11) and no icons.
