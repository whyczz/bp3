# CONSTRAINTS.md: what bp3 is built from, and what it ships

The owner-signed stack. Plans, red chairs and graders check any new
language, library or surface against this file, and
`scripts/check-constraints` (in `make lint`) checks the tracked
files. Adding anything takes the owner's sign-off (How to change).

## Languages

Each `lang` line names a language, how its files are recognized
(`ext`, `files`, `shebang`), where else it may run as an interpreter
(`runs-in`; only shebang words run anywhere), and its libraries
(`libs`). A library is anything a language pulls in: an OCaml
library, a node import, or a tool a bash script runs (owner,
2026-11-19: "they are tools, call them libraries, e.g. we pick
langs, but also libraries within the lang"). The `data` line lists
the files that are not code.
`docs/**` and `*.md` are prose: pseudocode in them is not a language.

```constraints
lang ocaml  ext .ml .mli  files dune dune-project    libs stdlib unix str yojson sqlite3 ounit2 qcheck-core qcheck-ounit
lang bash   ext .sh .bash  shebang bash sh           libs posix git jq yq sed awk find mktemp make gh shellcheck yamllint
lang zsh    files completions/_bp3  runs-in test/completion.sh  libs (completion builtins only)
data        ext .md .json .jsonl .yaml .tsv .txt .mmd .conf  files Makefile Brewfile .gitignore
```

The block is the only copy of the list. The prose here says why and
where; it never restates the list, so the two cannot drift.

Why some lines look the way they do:

- **zsh** is grandfathered for one file, the shell completion, and runs
  only in the test that checks it (`runs-in`). It is not an
  invitation to write zsh elsewhere.
- **bash** `libs` are the tools scripts run. `posix` means the POSIX
  and macOS base-system utilities (grep, head, tr, sort, cut, wc, cat,
  kill, ps, date, sleep, tar, ...); anything outside the base system
  (fzf, rg, expect) still needs a pitch. The lint checks Brewfile
  entries against this line; a script calling an unlisted tool with
  no Brewfile entry is for the grader to catch.

## Surfaces

| Surface | Allowed |
|---|---|
| bp3 CLI | `bin/bp3`, the `bp3 q` door, `bp3 harness`, `bp3 warden`, `bp3 release`, `bp3 db`, `bp3 repo`, `bp3 ticket` |
| skills | markdown, rendered per harness (`.claude`, `.pi`, `.agents`) |
| not without a quest and sign-off | web app, daemon or service, GUI, hosted database |

bp3 also drives harness CLIs (`claude`, `pi`, `codex`, `agy`). They are the
surfaces bp3 runs on, not libraries it uses.

## How to change

The owner, 2026-11-19:

> a. one constraint is the languages used, we should not add one unless
> it brings alot of value. here "brings alot of value" is a human
> decision, like I need to sign off, you need to convice, /teach me.
> b. surfaces, like bp3 is a CLI. we're not building a web app, etc
> unless it /quest'd out, e.g. brings value

1. A plan that adds a language, library or surface says so in its
   red chair (the constraints pass).
2. The agent makes a `/teach` pitch: why this, what it costs, and
   the boring alternative inside this file.
3. The owner answers in their own words.
4. One commit adds a Sign-off log row quoting those words and edits
   the block or the Surfaces table. An agent never adds a row alone,
   and a diff to this file without a new owner-words row is
   `needs_fix`.

Removing something works the same way.

## Sign-off log

| Date | Who | Owner's words | What it signed |
|---|---|---|---|
| 2026-11-20 | owner | "Approve as-is" (approval of `docs/quests/2026-11-19-constraints-context/`) | the Languages block and the Surfaces table as written; zsh grandfathered for `completions/_bp3` |
| 2026-11-20 | owner | "Add a `posix` word" (asked whether base-system utilities need listing one by one) | `posix` in the bash libs line: POSIX and macOS base-system utilities |
| 2026-11-20 | owner | "The file and its test" (asked what zsh's grandfathering covers) | `runs-in test/completion.sh` on the zsh line: zsh runs there and nowhere else |
| 2026-11-23 | owner | "okay, let's implement the first quest" (approval of `docs/quests/2026-11-23-fast-agy-induct/`) | `agy` added to driven harness CLIs in Surfaces |
| 2026-11-23 | owner | "Should Warden be its own top-level command — bp3 warden ... lock" (red-ink Round 2 of `docs/quests/2026-11-23-warden-v0/`) | `bp3 warden` added to `bp3 CLI` in Surfaces |
| 2026-11-23 | owner | "Top-level `bp3 release <quest>` AND `bp3 release --commit <sha>` (defaults to patch bump; sign off adding `bp3 release` to CONSTRAINTS.md)" (framing of `docs/quests/2026-11-23-quest-promote-release/`) | `bp3 release` added to `bp3 CLI` in Surfaces |
| 2026-11-24 | owner | "yep, lgtm, lets /quest both" + "i'm leaning towards 2, but i don't want to call the repos, i want bp3 install to do it" + "im leaning towards ticket" (red-ink of `docs/quests/2026-11-23-sqlite-control-plane/`) | `sqlite3` added to OCaml `libs`; `bp3 db`, `bp3 repo`, `bp3 ticket` added to `bp3 CLI` in Surfaces |
| 2026-11-24 | owner | "Drop test/pi-discovery.mjs too — remove lang node from CONSTRAINTS.md completely" + "Signed now — remove lang node (and pi-coding-agent) + harness extensions row from CONSTRAINTS.md" (red-ink of `docs/quests/2026-11-23-codebase-diet/`) | `lang node` (with `@earendil-works/pi-coding-agent`) and the `harness extensions` row (`extensions/bp3-pi`, workflow scripts) removed |
