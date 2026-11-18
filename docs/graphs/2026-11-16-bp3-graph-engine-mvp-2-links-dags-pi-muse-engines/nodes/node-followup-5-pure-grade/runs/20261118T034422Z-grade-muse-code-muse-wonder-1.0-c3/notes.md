# Grade notes — node-followup-5-pure-grade cycle 3 (run 20261118T034422Z-grade-muse-code-muse-wonder-1.0-c3)

Bound commit: 84be74a6ee6a97288269e37732a952820d982853

## Lessons
- Code-reviewer pass (rungs 1-4): NODE.md acceptance read first; bound commit is docs-only (NODE.md RESOLVED entry + run notes) over substantive ancestors 4ab3228/31b7c74/0ee41e2. The RESOLVED claim agrees with the code: --verify-verdict/--mechanical are in completions/_bp3 and completions/bp3.bash (0ee41e2, ancestor of bound commit) and ./test/completion.sh passes.
- Rung 3 runs: `node test/bp3g-grade.test.mjs` ok, `node test/bp3g-node.test.mjs` ok, `./test/completion.sh` ok — these cover pure audit, single cast, safe replay, all three pushbacks, fix-ledger, audit-reuse, and mechanical-cap fixtures.
- Regression gate not green: `timeout 240 make check` terminates at ./test/g.sh (Terminated: 15, exit 124); `timeout 60 ./test/g.sh` alone also times out with no output. Handoff/commit claim of `make check` exit 0 is not reproduced at the bound commit in this environment, so the regression row has no pass evidence.
- Verdict: needs_fix (standard). Only failing gated row: regression. A gate that never finishes cannot be borrowed as green; diagnose the test/g.sh hang/slowness and restore a completing green `make check` before re-grade. No whole-tape (rung 5b) read was needed; grade decided at rungs 1-4.
- Pure grade honored: no files in the work edited, no `bp3 g u` call made; verdict returned as data only.
