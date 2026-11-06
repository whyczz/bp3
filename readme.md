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

**Status: MVP scope agreed; implementation design in progress. No implementation yet.**

## Design

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

## Project skill checks

Install the tooling dependencies with `brew bundle` (Mike Farah yq v4, jq,
and ShellCheck), then run `make check`. This validates the YAML frontmatter
of canonical and installed skills and runs the installer regression tests.
No OCaml toolchain is required for these checks.
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

The product scope is agreed; the implementation design remains proposed.
Command names are not implemented commands. Worktrees are not a security
boundary; bypass is detectable, not preventable, and the Quest-to-master
approval entry path and runtime reliability still need concrete design and
verification.
