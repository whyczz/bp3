# verify notes — exp-followup-2-workflow-birth c1

- Fresh rung2: `git status --porcelain` empty before run-folder creation; bound commit 6f124a6 present, clean.
- Fresh rung3: `./bin/bp3 skills check` -> fresh [node-loop,bp3g-grade,bp3g-land,bp3g-node]; all workflow tests ok (grade/land/node/node-loop/conduct); `bash test/skills.sh` -> 134 assertions ok.
- Blocking gap: acceptance row "full conduct (node -> grade -> land) from foreign-dialect conductor root, zero read refusals" remains missing — evidence is mock-host fixtures only (bp3g-node/bp3g-conduct tests), no real conduct run observed. Per matrix rule, gated missing = fail.
- Lesson: mock fixtures prove prompt shape, not live dispatch; a real foreign-root conduct run is still required.
