---
node: brief.1
---

# brief.1 - accept-acceptance-test-heading

TL;DR
Teach `Brief.render` (`src/quest/brief.ml`) to extract `## Acceptance gates` first and fall back to `## Acceptance test` when absent or empty, backed by unit and property tests in `test/unit/test_brief.ml`.

## Acceptance gates

Design trace:

```text
$ Brief.extract_gates "## TL;DR\n\nhi\n\n## Acceptance gates\n\ngate body\n"
-> Some "gate body"
$ Brief.extract_gates "## TL;DR\n\nhi\n\n## Acceptance test\n\ntest body\n"
-> Some "test body"
$ Brief.extract_gates "## Acceptance gates\n\ngates win\n\n## Acceptance test\n\nfallback\n"
-> Some "gates win"
$ Brief.extract_gates "## TL;DR\n\nno gates\n"
-> None  # render emits "(NODE.md at <sha> has no Acceptance gates section: that is a finding)"
```

Runnable goal block:
- **objective:** Prevent cold-grader briefs from dropping acceptance gates when a `NODE.md` uses `## Acceptance test` instead of `## Acceptance gates` (Ticket `#10`).
- **prove by:** Unit tests + QCheck2 coverage in `test/unit/test_brief.ml` and `make check-full`.
- **done when:** `make check-full` exits `0`, `Brief.render` inlines `## Acceptance test` when `## Acceptance gates` is absent/empty, prefers `## Acceptance gates` when both exist, and still emits the missing-section finding when neither has content.

## Diagram

```text
NODE.md text
  |
  +--> section "Acceptance gates" (non-empty?) --yes--> inline in brief
  |                                            --no---> section "Acceptance test" (non-empty?) --yes--> inline in brief
  |                                                                                            --no---> missing-gates finding
```

## Pseudocode

```python
def extract_gates(md: str) -> str | None:
    for heading in ("Acceptance gates", "Acceptance test"):
        body = section(heading, md)
        if body is not None and body.strip() != "":
            return body
    return None
```

## Tables

| Field | Value |
|---|---|
| Intent | Eliminate false missing-gates findings in cold briefs for `## Acceptance test` `NODE.md` files (Ticket `#10`). |
| Kind | `code` |
| Lane | `micro` |
| Output | `Brief.extract_gates` in `src/quest/brief.ml`, unit tests in `test/unit/test_brief.ml`. |
| Acceptance | Fails today: `Brief.render` on a `NODE.md` with only `## Acceptance test` prints `(NODE.md at <sha> has no Acceptance gates section: that is a finding)`. |
| Depends on | none |

## Prose

In `predictor`'s `2026-11-25-house-spec-ir` quest, all 7 `NODE.md` files used `## Acceptance test` (matching `skills/red-ink/SKILL.md:298`). `Brief.render` only looked for `## Acceptance gates`, dropping inlined gates from every brief and forcing cold graders to read the full 1,029-line `QUEST.md`. Extracting via a tiny pure `Brief.extract_gates` keeps `Brief.section` clean and backwards-compatible while letting `Acceptance gates` remain the canonical primary heading.

Edge cases:
- Empty `## Acceptance gates` followed by non-empty `## Acceptance test`: falls back cleanly to `## Acceptance test`.
- Both headings non-empty: `## Acceptance gates` wins deterministically.
- Both headings absent or whitespace-only: emits the exact existing `(NODE.md at <sha> has no Acceptance gates section: that is a finding)` line.
