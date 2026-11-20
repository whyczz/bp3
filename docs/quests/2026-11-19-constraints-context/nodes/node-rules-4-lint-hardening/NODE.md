---
date: 2026-11-20
quest: ../../QUEST.md
node: rules.4
status: proposed
---

# rules.4 - lint-hardening (follow-up): close the holes the rules.2 grader found

## TL;DR

The rules.2 grader shipped `scripts/check-constraints` and probed it
in both directions. This node fixes three bugs, four false positives
(the quest's strongest attack: a lint that cries wolf) and the
command positions it misses. Each fix gets a planted row in
`test/check-constraints.sh` that fails before the fix and passes
after. Lookups also move into one awk pass, so cost stays flat as
the repo grows. Owner, 2026-11-20: "rules.4 follow-up node".

## Acceptance gates

Observed today (rules.2 grader, c8c5a99):

```text
$ rm CONSTRAINTS.md; ./scripts/check-constraints; echo $?
1                                  # silent; spec says exit 2 with a message
$ printf 'git status  # was (perl -pi) once\n' >> scripts/tool   -> FAIL interpreter perl   (false positive)
$ printf 'if python3 x; then :; fi\n' >> scripts/tool            -> ok                       (missed)
$ printf 'zsh -c true\n' >> scripts/tool                          -> ok                       (zsh is one file only)
```

Design trace:

```text
$ ./test/check-constraints.sh
check-constraints tests: ok (<16 + new rows> assertions)
$ ./scripts/check-constraints
check-constraints: ok (4 languages, <n> files)        # under 2s, one awk pass for lookups
```

```yaml
objective: the lint neither cries wolf on ordinary shell nor misses an interpreter in a common command position
prove by:
  - test/check-constraints.sh, one planted row per item below, each red on c8c5a99's script and green after
  - make check-full
done when:
  - every row in the table below has a planted case and passes
  - removing the comment-skip line turns the test red (the mutant dies)
  - the repo's own lint stays ok, and check-full is green
```

## Diagram

```text
line ─► drop trailing comment (# after whitespace) ─► blank quoted strings
     ─► split on | ; && || $( ` ( & and newline-ish words
     ─► skip VAR=value, reserved words (if then do else elif while until ! { time),
        wrappers (env exec command xargs nohup), their flags; strip make's @ - +
     ─► first word ∈ known ∖ allowed ─► FAIL
allowed interpreters = shebang words only (zsh has none, so zsh -c fails outside its file)
```

## Pseudocode

```python
block = read_block("CONSTRAINTS.md")          # missing file or empty block: exit 2 with the message
for line in shell_lines(f):                   # heredoc bodies skipped: <<WORD ... WORD
    line = strip_trailing_comment(blank_strings(line))
    for seg in split(line, SEPARATORS + ["&"]):
        word = first_word(seg, skip=ASSIGNMENTS | RESERVED | WRAPPERS, strip_make_prefix=True)
        if word in KNOWN and word not in SHEBANG_WORDS: fail(f, n, word)
shebang = parse("#!/usr/bin/env -S node --x")  # -> node, not -S
```

## Tables

| Field | Value |
|---|---|
| Intent | the lint stays trusted: no false alarms on ordinary shell, no easy smuggling |
| Lane | standard (changes a lint step that gates both gates) |
| Output | `scripts/check-constraints`, `test/check-constraints.sh`, `CONSTRAINTS.md` (the zsh `runs-in` and its sign-off row) |
| Acceptance | the planted rows below; fail today on c8c5a99's script |
| Depends on | rules.2 - constraints-lint |

| Item | Kind | Planted row |
|---|---|---|
| missing CONSTRAINTS.md | bug | exit 2, `no constraints block` |
| comment-skip unpinned | bug | `# old: git log \| python3 x` passes; the mutant without the skip fails |
| zsh allowed everywhere | bug | `zsh -c true` in a bash script fails `interpreter zsh`; a planted `runs-in` file passes (owner, 2026-11-20: "The file and its test": CONSTRAINTS.md's zsh line gains `runs-in test/completion.sh` with a sign-off row) |
| trailing comment with `;` `(` `\|` | false positive | `git status  # was (perl -pi) once` passes |
| heredoc body | false positive | a `<<'EOF'` body line starting `perl` passes |
| case arm alternatives | false positive | `ruby\|python3) echo ;;` passes |
| `env -S` shebang | false positive | `#!/usr/bin/env -S node --no-warnings` passes as node |
| `if` `then` `do` `!` `{` `time` | false negative | `if python3 x; then :; fi` fails |
| `xargs`, `nohup`, single `&` | false negative | `git ls-files \| xargs perl -pi` fails |
| Makefile `@` `-` `+` | false negative | `\t@python3 x` in a Makefile fails |
| make prefix stripped from every word (round 1) | fail open | `\tenv -i python3 x` and `\tgit ls-files \| xargs -0 perl -pi` in a Makefile fail |
| false heredoc start hid the file (round 1) | fail open | `x=$((1 << n))`, `<<END-OF`, `echo "<<X" ; cat <<EOF` each followed by a real `perl`/`python3` that fails |
| a heredoc or quote that never closes | fail closed | FAIL naming the line, never a silent blind spot |
| deleted or directory-symlink paths (round 1) | fail open | a tracked .sh deleted from disk is skipped and later files are still scanned; a dir symlink is skipped |
| CRLF shebang, `command -pv`, `<<\EOF`, `nohup` | follow-up | planted near misses and a nohup row |

## Prose

Known gaps that stay, stated rather than chased: a `bash -c "perl ..."`
string (strings are words by design), `execSync("python3 ...")` in
node, interpreters inside dune `(action (run ...))`, a nested
`sub/Makefile`, a `.sh` file with a python3 shebang (shellcheck flags
it later in `make lint`), and interpreter names outside the fixed list
(`python3.12`, `npx`). The grader's library-check edges (`brew 'jq'`,
`cask`, dune `;` comments, a node comment naming an import) go in
only where a planted row is cheap. Otherwise they stay listed in the
script header as gaps.

zsh: CONSTRAINTS.md grandfathers it for `completions/_bp3` only, so it
must not pass as an interpreter in a bash script. The allowed set
becomes the shebang words (`bash sh node`), not every lang name.
