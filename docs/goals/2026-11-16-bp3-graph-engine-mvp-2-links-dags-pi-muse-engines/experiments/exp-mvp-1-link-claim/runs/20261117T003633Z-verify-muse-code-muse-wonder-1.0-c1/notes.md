# Verify notes — exp-mvp-1-link-claim c1
- Claim: run_id 20261117T003633Z-verify-muse-code-muse-wonder-1.0-c1 via bp3link_8bd943029dc1205cb6522d4d336209ac.
- Fresh evidence: git HEAD 09b9d8d01646ca0f2faeb273bbf227aaa9c43fb3; ./test/link.sh -> link tests: ok (covers mint+claim, one winner/CAS, by-session join, session-id offered vs not, run-config replaces InitRecord, stale cleanup, quoting).
- Pi: node --test extensions/bp3-pi/test/bp3-pi.test.mjs -> pass 13 fail 0, incl. missing bp3-pi extension refuses E_SETUP before any spawn.
- Depth cap: src/quest/harness.ml:2219 `if depth > thresholds.Config.depth_cap then`.
- Adherence: handoff run folder has tape.log+notes.md; node-loop.js:7 moves through bp3 q u called directly by author child.
- Verdict: pass — all gated rows re-run fresh, none deferred/blocking.
