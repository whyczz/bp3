---
date: 2026-11-19
quest: ../../QUEST.md
node: ctx.1
status: proposed
---

# ctx.1 - context-file: how other people build this, in one page

## TL;DR

`CONTEXT.md` at the repo root is the common-sense ground: for each of
the owner's questions (orchestration, storage, scaling, human-LLM
interaction, learning and org scale, the pre-LLM engineering canon)
plus review loops, what other builders do, one line per claim, each
with a source and the date it was checked, and where bp3 differs and
why. The canon section is filtered: a principle is kept when the
human constraint it was written against still binds for agents or
the owner, marked inverted when it no longer does, and amplified
when agents make it worse. It is distilled from the
dossier `docs/dossiers/agent-harness-landscape.md`, whose Re-run
section holds the searches that refresh it.

## Acceptance gates

Observed today:

```text
$ ls CONTEXT.md
ls: CONTEXT.md: No such file or directory
```

Design trace:

```text
## Q2 Storage
- Most open harnesses keep state in plain files in the repo, not a db
  (<source>, checked 2026-11-19). bp3: an append-only ledger.jsonl, written only by bp3 q.
$ grep -c '^- ' CONTEXT.md
31
$ grep -c -E '^- .*https?://.*[0-9]{4}-[0-9]{2}-[0-9]{2}|^- .*dossiers/.*[0-9]{4}-[0-9]{2}-[0-9]{2}' CONTEXT.md
31
```

```yaml
objective: a session can read in two minutes how others solve what bp3 solves
prove by:
  - the two grep counts above (every claim line has a source and a date)
  - the grader opens three random sources and checks each claim against it
done when:
  - sections Q1-Q6 and Review loops exist, each with at least three sourced claims
  - every Q6 principle carries its verdict (transfers, inverts, amplifies)
  - every claim line carries a source link and a YYYY-MM-DD checked date
  - a "bp3 lessons" section holds our own dated lessons (tier.1 bash runner first)
  - the refresh rule is stated at the top, and the owner reads it at land
```

## Diagram

```text
saved searches (dossier Re-run) ──► dossier (long, every source) ──► CONTEXT.md (short, claims)
        ▲                                                                   │
        └──── claim older than 90 days, about to be cited: re-run first ◄───┘
```

## Pseudocode

```python
for q in ["Q1 orchestration", "Q2 storage", "Q3 scaling", "Q4 human-LLM",
          "Q5 learning and org", "Q6 engineering canon (filtered)", "Review loops"]:
    section(q, claims=[c for c in dossier.claims(q) if c.seen_in >= 2 or c.first_party])
    # each claim: one line, link, checked date, then "bp3:" only where we differ
section("bp3 lessons", our_dated_lessons)
```

## Tables

| Field | Value |
|---|---|
| Intent | ground for the common-sense pass: "how would another team build this?" |
| Lane | micro |
| Output | `CONTEXT.md` |
| Acceptance | the greps plus the grader's three-source spot check; fails today (no file) |
| Depends on | the dossier, written during framing (not a node) |

## Prose

The owner, freezing the idea: "I feel like we're making strange
decisions. for example doing research on how other people build
their agent systems gives us ground for common sense." The dossier is
the long record; CONTEXT.md is what a session actually reads, so it
stays short: claims seen in at least two places or stated first-party,
and nothing that only one forum comment said.

The refresh rule (owner, 2026-11-19): a claim older than 90 days is
re-checked with its saved search before a quest or red chair cites it.
No calendar job.
