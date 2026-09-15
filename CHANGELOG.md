# Changelog

## 0.4.1 — 2026-09-15

- Panel: click a thread (or the fresh-session row) and the lines under its title slide aside for its report:
  last verdict, fingerprint, probe facts, earlier probes, evidence with what was reverted, Copy report; nothing
  else moves. Right-click for Probe, Copy report, Reveal folder. Settings is a page of its own. Fresh session sits
  below the threads; the header is the chip face with one short line per fact; the panel is a little narrower.
  The Report window is gone (the report lives in the rows; `nerfed report` remains).
- Upgraded: a move to a better model (a rollout such as gpt-5.6-sol → gpt-6-sol) is a state of its own, shown in green
  and notified, from the passive scanner or the fingerprint. Better or worse is decided by `compare_models`, not a
  fixed list: Codex's catalog succession pointer, hidden internal models, the generation and size tier in the slug,
  then Codex's own ranking, the highest supported reasoning effort and the context window.
- The headline is "All clear" unless something is downgraded or suspicious; an unverified count (a verdict from
  another account, or from before accounts were tracked) follows on the next line instead of being the headline.
- Fixed: the SessionStart hook crashed (silently, in the fail-safe) on a keyword collision, so session starts were
  not logged.
- A failed attempt (Invalid) is no longer shown as a verdict: the row keeps its last verdict and offers Retry; the
  report notes the attempt. A verdict from another account reads "Unverified · Match, another account"
  instead of a greyed-out Match.
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
