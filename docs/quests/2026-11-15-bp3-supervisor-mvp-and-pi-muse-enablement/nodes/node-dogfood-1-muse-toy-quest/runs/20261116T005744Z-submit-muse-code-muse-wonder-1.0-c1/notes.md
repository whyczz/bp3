# Run notes — exp-dogfood-1-muse-toy-quest c1 (muse)

## What was built

- `flappy.html` in this run folder: a single-file three.js
  Flappy Bird demo. It reuses the exp's own word `flappy`
  for the file name (naming discipline: one concept, one
  spelling). The bird flaps on click/Space, pipes scroll,
  score counts passed pipes, collision or leaving the
  field ends the game, and click restarts.

## Lessons

- The exp asks for the artifact plus traces in the exp's
  `runs/` folder, so the demo lives beside `tape.log`
  rather than in a new top-level folder — no new spelling
  or location had to be invented.
- Verification here is static plus a syntax check: this
  run did not open a browser, so "page opens" is checked
  by HTML/JS structure, not by rendering. Graders should
  open `flappy.html` to confirm visually.
- Pre-existing dirty files from other exps were left
  untouched; only this run's files were committed.
