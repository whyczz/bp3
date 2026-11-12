---
date: 2026-11-07
quest: ../QUEST.md
exp: 1
status: canceled
---

# Exp 1 — Timed baseline: where the four hours go

## TL;DR

**Killed by the owner (2026-11-11): the owner ran the Pi loop by
hand and convicted it directly — “I ran the Pi myself and it
sucks.”** Measuring a convicted system is ceremony, so no
baseline is run and nothing here gates the Quest. What follows
is the original sketch, kept as a fossil.

Status: **canceled, never run.**

- Intent: attribute the current loop's cost before changing it.
- Lane: standard
- Output: a recorded breakdown for one toy exp on today's Pi crew:
  framing, spawn-to-ready, context load, execution, checks, review,
  and idle-blocked time, plus context tokens per Run.
- Acceptance: the breakdown exists with numbers observed from Board
  timestamps and session usage. Fails today: the canceled Quest's
  scorecard records human-active minutes and provider cost as
  unmeasured, and the Board snapshot hardcodes cost to null.
- Substeps: 1.1 add token/usage accounting to the snapshot (turn
  events with input/output/cache tokens); 1.2 run one toy exp and
  publish the phase breakdown; 1.3 state the verdict: context,
  ceremony, provider, or scheduling dominates. If ceremony or
  provider dominates, this Quest cancels early with that finding.
- Depends on: none.
