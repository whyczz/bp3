# Verify notes — exp-config-1-bp3-config c2

- Fresh evidence only: re-ran ./test/config.sh (config tests: ok) and ./bin/bp3 config --source at bound commit 3c47fe5; derivations count drifted 260→262 due to intervening runs, not a failure — config.sh itself asserts derivations folded in.
- Diff is scoped correctly: ensure_dir now raises non-EEXIST mkdir failures (attributed EACCES test), dead Config.thresholds removed, thresholds claim scoped to view/mvp.1/mvp.3 in comments and help text, tracked-files guard added.
- Lesson: derivations count in a quoted matrix is a moving number; judge by the test, not the exact count.
