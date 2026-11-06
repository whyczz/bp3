# bp3

The state-aware harness/skills you talk to: an evolving Board, Worker
coordination, review, and controlled integration. One monorepo — this repo,
git-renamed from bp3-control — with a core/plugins split (protocol, board,
control, runtime as core; harness adapters, packs, and future wardens/cron
as plugins) and all design docs. The generic bp3-yap-skills library stays a
separate repo.

**Branch convention:** `master` is the default/integration branch, never `main`.
Quest implementation stays on `quest/<name>` until explicitly promoted; pushing
`master` does not authorize pushing or promoting Quest branches.

**Status: MVP Quest active. Exp 1's five acceptance stages pass; its source
checkpoint is on `quest/bp3-mvp`, not promoted to `master`. Exp 2 review/auto-land
and self-hosted promotion are not implemented.**

Start with the [genesis runbook](docs/genesis.md) for build instructions,
verified live Worker/recovery evidence, code map, limitations, and reproducible
drills. The [active Quest](docs/quests/2026-11-05-bp3-mvp.md) tracks progress.

```sh
opam install . --deps-only --with-test
opam install ocamlformat.0.29.0
dune build @all
make check
./bin/bp3 --help
```

The core is OCaml + SQLite; a small TypeScript pi bridge supplies lifecycle
signals. `bp3 context` currently emits a JSON recovery snapshot. There are no
success-shaped stubs for review, land, promotion, or push.

## Design

The [genesis contract](docs/designs/bp3-genesis-contract.md) resolves the current
Exp 1 implementation boundary. The broader product direction below is not a
claim that every proposed capability is already built.

Start with the [MVP](docs/designs/bp3-control-mvp.md): agreed product scope,
user/Controller/Worker responsibilities, self-dogfood acceptance, and proposed
implementation boundaries, experiments, and next design slices.

The [original architecture sketch](docs/designs/bp3-control.md) is retained as
history. It is superseded by the MVP, not a second live specification.

- **Quest:** an evolving pursuit of a real, demo-able outcome.
- **exp:** an outcome-defined unit of delegated work, with explicit prerequisites.
- **Controller:** the live session running control skills; replaceable without losing coordination state.
- **Board:** durable coordination state in SQLite, accessed through controlled operations.
- **Worker:** a dedicated execution session that produces artifacts and evidence, not its own approval.

The goal is more learning and delivery per unit of human attention. Start with
one OCaml monorepo and CLI, SQLite, pi/Zellij, and cooperative Git worktrees.
All coding work goes through exps and Workers; the Controller coordinates,
reviews, and owns landing mechanics, but does not author code. Ceremony scales
with blast radius across micro, standard, and high-risk lanes, and one-off
fixes take a taxi lane with no Quest conversation.

A deterministic runtime multiplexes 3-10 Worker and reviewer processes;
the Controller multiplexes decisions from Board snapshots, not panes. Exps
auto-land into their Quest branch under strict check, review, target, and
budget gates, with a compact notice to the main session. The human steps in
at Quest-to-master to understand the integrated result and authorize promotion;
push is separately scoped. Waiting is event-driven, not a model polling loop.

First dogfood: use bp3 to build **bp3 itself**, after a hand-built genesis
kernel, through a one-week shakedown that prices friction and produces a
hardening list. esc3 follows as the transfer test, not the first proof. Prove
useful output, independent checks, blocker briefings, and Controller restart
recovery—not just parallelism.

## One Quest workspace in Ghostty + Zellij

On macOS, with Ghostty, Zellij, pi and Node installed:

```sh
./bin/bp3-zellij-init docs/quests/2026-11-05-bp3-mvp.md \
  "Read this Quest and recommend the next step; do not start work yet."
# A unique slug works too: ./bin/bp3-zellij-init bp3-mvp "Your prompt"
```

This starts a dedicated Zellij session with a **Controller** tab and opens a new
Ghostty window attached to it, with saved-window restoration disabled for that
instance only (your normal Ghostty configuration is untouched). pi receives the
prompt literally from a private file, not interpolated shell code or visible
pane argv. The session name and reattach argv are printed as JSON. Local reservation/prompt/session files live
under `.bp3/sessions/` (ignored; do not publish them).

The Controller gets `BP3_QUEST_FILE` and `BP3_SESSION`. `bp3 launch` fills in a
missing `session_name` from that binding and refuses a conflicting explicit
name. The current launcher creates **one full-size Worker terminal per tab**,
with tab/status bars and no focus stealing. Launch responses return diagnostic
`tab` IDs; authoritative pane identity still comes from the bridge handshake.
Outside a bound Controller shell, `session_name` remains required.

The helper does **not** initialize or rewrite a Board, start a runtime, change a
branch, send a brief, or authorize landing/pushing. Use a runtime built with the
tab launcher, frozen as usual; existing frozen runtimes do not hot-upgrade.
Desktop state is not Board authority or a pi readiness receipt.

An existing session or local reservation is refused, not silently re-created or
sent a second prompt. To reopen a live workspace, explicitly attach from Ghostty
(`zellij attach SESSION`), or use
`open -na Ghostty --args --window-save-state=never -e zellij attach SESSION`.
After a partial failure, inspect the private reservation and real session first;
no automatic respawn, input injection or deletion is attempted. A successful
`open` means the OS accepted a window request, not that a human saw it.

## Project skill checks

Install the tooling dependencies with `brew bundle` (Mike Farah yq v4, jq,
and ShellCheck). With the core dependencies above, `make check` validates the
core, adapter and formatting, the YAML frontmatter of canonical and installed
skills, and the installer regressions. For skill-only work, run
`./scripts/check-skills skills .pi/skills .agents/skills .claude/skills` and
`./test/skills.sh` without installing OCaml.
Descriptions containing a colon followed by a space must be quoted or use
a YAML block scalar; the installer validates every source before writing
any generated copies.

Regenerate project skills with `./bin/bp3 skills install --harness=all`.
Pi installs also merge per-skill exclusions into `.pi/settings.json`, so
Pi loads `.pi/skills` rather than warning about duplicate `.agents/skills`
copies. Codex/Muse files and unrelated skills remain intact; existing Pi
settings are preserved. The project exclusions are committed so a fresh
clone gets the same discovery behavior.

Optional verification against an installed Pi (Node.js required):

```sh
PI_PACKAGE_ROOT=/path/to/@earendil-works/pi-coding-agent node test/pi-discovery.mjs
```

The product scope is agreed; implementation beyond genesis remains proposed.
Only commands listed by `./bin/bp3 --help` (plus `skills install`) are currently
implemented. Worktrees are not a security boundary; bypass is detectable, not
preventable. Quest-to-master approval, independent integration gates, full restore,
and production runtime hardening still need design and verification.
