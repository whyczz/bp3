# bp3-control

The state-aware harness/skills you talk to: an evolving Board, Worker
coordination, review, and controlled integration.

**Status: MVP scope agreed; implementation design in progress. No implementation yet.**

## Design

Start with the [MVP](docs/designs/bp3-control-mvp.md): agreed product scope,
user/Controller/Worker responsibilities, esc3 dogfood acceptance, and proposed
implementation boundaries, experiments, and next design slices.

The [original architecture sketch](docs/designs/bp3-control.md) is retained as
history. It is superseded by the MVP, not a second live specification.

- **Quest:** an evolving pursuit of a real, demo-able outcome.
- **exp:** an outcome-defined unit of delegated work, with explicit prerequisites.
- **Controller:** the live session running control skills; replaceable without losing coordination state.
- **Board:** durable coordination state in SQLite, accessed through controlled operations.
- **Worker:** a dedicated execution session that produces artifacts and evidence, not its own approval.

The goal is more learning and delivery per unit of human attention. Start with
one CLI, SQLite, pi/Zellij, and cooperative Git worktrees. All execution work
goes through exps and Workers; the Controller coordinates and owns landing
mechanics. Human permission is required for land and push. Waiting is event-driven,
not a model polling loop.

First dogfood: use bp3 to implement **esc3**, preserving esc2's MVP capabilities
with clearer data and queryable day/week recaps. Prove useful output, independent
checks, blocker briefings, and Controller restart recovery—not just parallelism.

The product scope is agreed; the implementation design remains proposed.
Command names are not implemented commands. Worktrees are not a security
boundary; the approval entry path and runtime reliability still need concrete
design and verification.
