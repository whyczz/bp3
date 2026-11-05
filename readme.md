# bp3-control

The state-aware harness/skills you talk to: an evolving Board, Worker
coordination, review, and controlled integration.

**Status: design proposal. No implementation yet.**

## Design

Read [Exploratory Quests, coordinated exps](docs/designs/bp3-control.md)
for the architecture, data models, operations, acceptance checks, proposed
delivery milestones, and open questions.

- **Quest:** an evolving pursuit of a real, demo-able outcome.
- **exp:** an outcome-defined unit of delegated work, with explicit prerequisites.
- **Controller:** the live session running control skills; replaceable without losing coordination state.
- **Board:** durable coordination state in SQLite, accessed through controlled operations.
- **Worker:** an isolated execution session that produces artifacts and evidence, not its own approval.

Start with one CLI. Version execution inputs, run independent exps in parallel,
and review committed artifacts with repeatable checks and demos. Complete the
Quest when its demonstrated outcome is accepted. Hardening is a new Quest
based on the completed exploratory one.

The design remains a proposal; command spellings do not imply implemented
commands. Publishing requires recorded human authorization. Sandbox and
approval enforcement are open design questions, not claimed security guarantees.
