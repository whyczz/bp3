# verify notes — exp-mvp-4-diagram-emit c1

- Fresh: git status clean, HEAD == bound commit fe6efe7.
- Fresh: ./test/diagram.sh -> "diagram tests: ok" (exit 0).
- Fresh: ascii/mermaid/json all emit live rollup; node shows (handed_off, cycle 1); honest "generated from live state at <ts>" label; waves + starved sections present.
- Lesson: judge on rerun output, not the handoff matrix; ledger.jsonl path in matrix does not exist as a file — state corroborated via live diagram json instead.
- Verdict: pass.
