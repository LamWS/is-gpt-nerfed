# Changelog

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
- Codex pet "Inspector Astra" for `/pet`.
