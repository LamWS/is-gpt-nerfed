# does-gpt-cheat

**Is the model answering you the one you selected?** does-gpt-cheat is a Codex plugin that watches your
Codex desktop / CLI threads for silent model downgrades and lets a snarky Codex pet break the news:

> 🎉 Congrats! You've been downgraded! You asked for gpt-6-astra; the fingerprint says gpt-5.6-luna (91%, 3/3 answers). Enjoy the discount you didn't ask for.

Everything runs locally, uses only documented Codex extension points (plugins, hooks, skills, pets, the
app-server protocol) and modifies nothing inside Codex. The fingerprint bank, scorer and probe prompts come
from [ModelTrace](https://github.com/xqy2006/ModelTrace) by xqy2006 (MIT); see *Credits*.

## How it works

Two independent layers, one pet.

**1. Passive scan, zero tokens, every turn.** Codex writes every thread to a rollout file and records, per turn,
the model and reasoning effort it *asked for*, every settings change the app applied, and the model's context
window. A lifecycle hook scans the new bytes after each turn and flags:

| finding | severity | meaning |
| --- | --- | --- |
| `silent_model_change` | hard | the model changed between turns with no settings change |
| `silent_effort_change` | hard | reasoning effort dropped with no settings change |
| `hidden_model` | hard | a model the catalog marks `visibility=hide` (e.g. `gpt-reserve`) ran a turn |
| `context_window_change` | hard | the context window shrank mid-session (a different model class answered) |
| `applied_model_change` | soft | the app applied a lower-tier model through thread settings: you, or the app ([openai/codex#28211](https://github.com/openai/codex/issues/28211))? |
| `service_tier_change` | info | the Fast / priority tier was dropped |

**2. Active fingerprint probe, on your schedule.** The thread is forked `ephemeral: true` three times at its
last completed turn through Codex's own app-server, the same mechanism behind `/side`. Each fork is asked, with no
tools, for ~300 "random" integers in 1..355. Language models are not random-number generators: the value
distribution and the ordered-block structure of such a sequence form a fingerprint that ModelTrace's calibrated
bank attributes to a specific model (GPT samples enrolled from the official Codex subscription; cross-validated
accuracy 95.5% with one answer, 100% with three). The thread's declared model is compared with the top candidate:

| verdict | meaning |
| --- | --- |
| `MATCH` | fingerprint = declared model |
| `MISMATCH (downgrade / upgrade / lateral)` | fingerprint ≠ declared model |
| `DOWNGRADED!` | hard passive evidence exists, whatever the fingerprint says |
| `UNLISTED` | the declared model is not in the bank; a look-alike is reported, no verdict |
| `INVALID` | no usable sample (tool use attempted, refusal, truncation, transport error) |

The three forks run in parallel (about 40 s per probe on a small thread), never touch your context, are never
written to disk and never appear in the Codex UI. Inside a `/side` conversation the model answers the same
challenge itself instead; the numbers stay in the ephemeral side thread.

**The pet.** Verdicts arrive as a card in the thread, a macOS notification titled with the pet's name, a system
message at the next turn boundary, and (for downgrades) the Codex notification sound. A custom pixel-art pet,
*Inspector Astra*, is installed into `~/.codex/pets/` for `/pet`. Optional Guard-style halt: with
`halt_on_mismatch` on, work tools are denied after a mismatch until you explicitly say to resume.

## Install (macOS, Codex desktop app or CLI ≥ 0.117)

```bash
git clone https://github.com/<you>/does-gpt-cheat ~/does-gpt-cheat && cd ~/does-gpt-cheat && ./install.sh
```

`install.sh` registers this folder as a local plugin marketplace (`codex plugin marketplace add` + `codex plugin add`,
with a fallback that appends two blocks to `~/.codex/config.toml`), installs the pet, and runs `dgc doctor`. Needs
only the system `python3`; the codex binary is found on `PATH` or inside the ChatGPT/Codex app bundle
(`CODEX_BIN=/path/to/codex ./install.sh` to override).

Then:

1. Restart the Codex app (plugins load on start).
2. Trust the plugin's hooks once: Codex CLI → `/hooks` → does-gpt-cheat → trust; the desktop app asks in the plugin's settings.
3. In any thread say `$does-gpt-cheat`, or `/side $does-gpt-cheat` to keep it out of your context.

From another machine, `codex plugin marketplace add <owner>/does-gpt-cheat` then `codex plugin add does-gpt-cheat@does-gpt-cheat`
works too (Codex supports git marketplaces); run `./install.sh` from the checked-out copy for the pet and the doctor.

Uninstall: `./uninstall.sh` (add `--purge` to delete the local ledger). Codex caches a copy of the plugin under
`~/.codex/plugins/cache/`; after changing the code, run `./install.sh` again so the cache is refreshed.

## Using it

```bash
./bin/dgc report                      # every probe + passive findings
./bin/dgc explain <probe-id>          # attribution table, per-fork token usage, errors
./bin/dgc explain --method            # how the verdict is made
./bin/dgc audit --days 7              # zero-token scan of every rollout of the last week
./bin/dgc status                      # schedule state per active thread
./bin/dgc doctor --fork               # proves an ephemeral fork works, with zero inference
./bin/dgc config set frequency turns:8   # or 30m, 2h, manual
./bin/dgc config set halt_on_mismatch true
./bin/dgc probe now --thread <id>     # probe any persisted thread from a terminal
```

In a thread: `$does-gpt-cheat` runs a probe of *that* thread (the model reads `CODEX_THREAD_ID`); if the model's shell
is sandboxed without network, the probe is queued and runs right after the turn ends. `/side $does-gpt-cheat` makes the
side conversation answer the challenge directly.

Automatic mode (`mode=auto`, default): each main thread keeps its own counter; when `frequency` is reached the Stop hook
launches a detached worker that forks *that* thread. Subagent threads are excluded. `mode=nudge` only reminds you.

### Configuration (`~/.codex/does-gpt-cheat/config.json`)

| key | default | meaning |
| --- | --- | --- |
| `frequency` | `turns:8` | `turns:N`, `Nm`, `Nh` or `manual` |
| `mode` | `auto` | `auto` runs a background probe when due; `nudge` only reminds |
| `queries` | `3` | ephemeral forks per probe (1–3; 3 is calibrated at 100% CV accuracy) |
| `parallel` | `true` | run the forks concurrently |
| `languages` | `zh,en` | probe prompt language pool |
| `passive` | `true` | rollout scan on every turn |
| `notify` / `notify_on_ok` | `true` / `false` | macOS notifications |
| `announce_ok` | `false` | also push MATCH verdicts into the thread |
| `sound` | `true` | Codex notification sound on a downgrade |
| `halt_on_mismatch` | `false` | deny work tools after a mismatch until `dgc resume` |
| `pet_name` | `Inspector Astra` | who speaks |
| `codex_bin` | auto | path to the codex binary |

## What it cannot do

- It cannot see which weights actually served a request; "declared model" is what Codex asked for. A server-side swap
  that keeps the slug is visible only through behaviour (the fingerprint) or side effects (context window).
- Attribution is closed-set: a model outside the bank is mapped to its nearest look-alike. A quantised or otherwise
  "dumbed-down" variant with the same slug only shows if its number distribution drifts.
- Probes fork from persisted history; a turn still in flight is not included. Probes spend inference on your account
  (three short answers, mostly cached input).
- The probe's forks run in a private app-server process, so if routing were tied to the desktop's own connection
  rather than to the conversation and account, fidelity would be lower than the desktop's own `/side`. Unverifiable.

The ledger under `~/.codex/does-gpt-cheat/` (`probes/*.json`, `sessions/*.json`, `events.jsonl`) is plain JSON; read it.

## Development

```bash
python3 -m unittest discover -s tests -v   # scanner, verdicts, scheduler, offline end-to-end via tests/fake_codex.py
python3 -m unittest tests.test_parity -v   # the Python scorer must match ModelTrace's JS core to 1e-9 (needs node)
./bin/dgc selftest
python3 tools/make_pet.py                  # regenerate the pet spritesheet (pure Python)
```

Layout: `plugin/` is the Codex plugin (`.codex-plugin/plugin.json`, `skills/does-gpt-cheat/`, `assets/`),
`.agents/plugins/marketplace.json` makes this repo a marketplace, `bin/dgc` is a convenience wrapper.

## Credits

- [ModelTrace](https://github.com/xqy2006/ModelTrace) (xqy2006, MIT): the fingerprint method, the calibrated bank
  (`plugin/assets/modeltrace/unified_bank.json`, provenance in `provenance.json`), the probe prompts, and ModelTrace
  Guard's fork-and-verify sequence which this plugin follows.
- [hlwy-ai-checker](https://github.com/hanlinwenyuan/hlwy-ai-checker) for first using random-number bias to check API channels.

MIT license.
