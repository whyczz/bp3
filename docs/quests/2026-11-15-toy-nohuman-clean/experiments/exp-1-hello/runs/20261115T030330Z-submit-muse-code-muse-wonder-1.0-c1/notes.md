# Notes — exp-1-hello c1

- Name reused: `hello.txt` reuses the repo word `hello` (exp `exp-1-hello`); no new vocabulary coined.
- Work: created `docs/quests/2026-11-15-toy-nohuman-clean/hello.txt` with the single exact line `hello from no-human clean` plus trailing newline, matching the prior `hello from solo clean` byte convention.
- Verified: `od -c` shows the exact bytes and the acceptance string comparison prints `ACCEPTANCE_PASS`.
- Lesson: check the prior toy's committed bytes before writing; the acceptance line includes the trailing newline by house convention.
