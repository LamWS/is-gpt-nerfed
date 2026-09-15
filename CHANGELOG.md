# Changelog

## 0.4.1 — 2026-09-15

- Panel: click a thread (or the fresh-session row) to open its report in place: fingerprint, probe facts, earlier
  probes, evidence with what was reverted; right-click for Probe, Copy report, Reveal folder. Fresh session sits
  below the threads, the face is larger, the panel a little narrower. The Report window is gone (the report lives
  in the rows; `nerfed report` remains).
- Probes: a Suspicious first round no longer triggers a second one by default (`confirm_uncertain` is opt in), so a
  probe costs three answers.
- Scanner: Codex's usage-limit snapshot in the rollout is not read as a serving signal (it is the last limit family
  Codex parsed from the headers, not the bucket the turn was charged to); the "at the usage limit" label only uses
  the default family.

## 0.4.0 — 2026-09-15

First public release.

- Passive scanner: silent model / reasoning-effort / context-window changes and hidden internal models, read from
  the thread's own rollout on every turn (zero tokens).
- Active probe: three parallel `ephemeral: true` forks of the thread through Codex's app-server, attributed with
  ModelTrace's calibrated fingerprint bank; confidence-gated verdicts (Match / Suspicious / Downgrade / Downgraded /
  Unlisted / Invalid) with an automatic confirmation round and one automatic transport retry.
- Busy threads are forked at their newest finished turn, or waited for.
- Fresh-session probe: what does a brand-new session get right now?
- Accounts: probes are tagged with a hash of the signed-in Codex account; verdicts from another account (or from
  before tracking) are shown as unverified and re-probed.
- Hook trust: `nerfed hooks status|trust`; the installer offers to record trust (Codex skips untrusted hooks silently).
- Activity log (`nerfed log`), report, explain, evidence, audit.
- Menu bar app for macOS 26 (Liquid Glass): status, fresh session, active threads with verdicts and evidence,
  settings, report; red paw on a confirmed downgrade, orange when suspicious. Screenshot mode hides thread titles.
  The plugin is bundled inside the app, which installs it into Codex on first run.
- `nerfed probe now` opens an interactive session picker (vendored simple-term-menu) when run from a terminal.
- Fresh-session heartbeat (`fresh_frequency`): probe a brand-new session every N minutes regardless of activity.
- Hooks are fail-safe: the entry point never exits non-zero, and reinstalls keep previous version paths resolvable.
