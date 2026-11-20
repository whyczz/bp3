#!/usr/bin/env bash
# check-constraints fixtures (constraints-context rules.2): one planted
# repo per case on the rules.2 case table, each a copy of a clean repo
# plus one break; every break exits 1 and names its file, the clean
# repo and the near misses (a comment or a string naming python) pass,
# and no block exits 2. Fixture tier.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
lint="$root/scripts/check-constraints"
work=$(mktemp -d "${TMPDIR:-/tmp}/bp3-check-constraints.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
checks=0
fail() { echo "FAIL: $*" >&2; exit 1; }
# a clean repo: one file per language and a planted block
clean="$work/clean"
mkdir -p "$clean/src" "$clean/scripts" "$clean/ext"
cat > "$clean/CONSTRAINTS.md" <<'EOF'
# planted
```constraints
lang ocaml  ext .ml  files dune  libs unix yojson
lang bash   ext .sh  shebang bash sh  libs git jq
lang node   ext .mjs  shebang node  libs node:* @scope/pkg
lang zsh    files completions/_x  runs-in scripts/zt  libs (builtins)
data        ext .md .json .txt  files Brewfile Makefile
```
EOF
printf 'let () = ()\n' > "$clean/src/a.ml"
printf '(library (name mine) (libraries unix yojson))\n(executable (name main) (libraries mine))\n' > "$clean/src/dune"
printf '#!/usr/bin/env bash\n# port of the python version\necho "then run python3 by hand"\ngit status\n' > "$clean/scripts/tool"
printf 'import fs from "node:fs";\nimport { x } from "@scope/pkg/sub";\nimport y from "./local.mjs";\n' > "$clean/ext/a.mjs"
printf '{"name": "x"}\n' > "$clean/ext/package.json"
printf 'brew "jq"\n' > "$clean/Brewfile"
printf 'notes\n' > "$clean/notes.txt"
mkdir -p "$clean/docs" && printf 'print(1)\n' > "$clean/docs/sketch.py"   # docs/ is prose
# rules.4: near misses that must pass (comments, heredoc bodies, case
# arms, a lookup), a lang with no shebang, an env -S shebang, a Makefile
mkdir -p "$clean/completions"
printf '#compdef x\n' > "$clean/completions/_x"
printf '#!/usr/bin/env bash\nzsh -c true\n' > "$clean/scripts/zt"   # runs-in: zsh may run here
printf '#!/usr/bin/env -S node --no-warnings\nconsole.log(1)\n' > "$clean/scripts/envs"
printf 'all:\n\techo ok\n' > "$clean/Makefile"
cat > "$clean/scripts/near" <<'EOF'
#!/usr/bin/env bash
# old: git log | python3 x
git status  # was (perl -pi) once
cat <<'DOC'
perl is only named here; python3 | ruby too
DOC
case "$1" in
  ruby|python3) echo "named, not run" ;;
esac
command -v python3 > /dev/null
EOF
(cd "$clean" && git init -q && git add -A)
run() { # case-dir -> rc, output in $work/<case>.out
  local rc=0
  (cd "$1" && "$lint") > "$1.out" 2>&1 || rc=$?
  echo "$rc"
}
[ "$(run "$clean")" = 0 ] || fail "clean repo failed: $(cat "$clean.out")"
grep -qx 'check-constraints: ok (4 languages, 12 files)' "$clean.out" || fail "clean ok line: $(cat "$clean.out")"
checks=$((checks + 2))
plant() { # name: a fresh copy of the clean repo at $work/<name>
  rm -rf "${work:?}/$1"; cp -R "$clean" "$work/$1"
}
want() { # name want-rc want-line: stage the plant, run, check
  (cd "$work/$1" && git add -A)
  local rc; rc=$(run "$work/$1")
  [ "$rc" = "$2" ] || fail "$1: exit $rc, want $2: $(cat "$work/$1.out")"
  grep -qxF -- "$3" "$work/$1.out" || fail "$1: want [$3], got: $(cat "$work/$1.out")"
  checks=$((checks + 1))
}
plant py;        mkdir "$work/py/tools"; printf 'print(1)\n' > "$work/py/tools/x.py"
want py 1 'check-constraints: FAIL tools/x.py: language .py not in CONSTRAINTS.md'
plant shebang;   printf '#!/usr/bin/env python3\nprint(1)\n' > "$work/shebang/scripts/gen"
want shebang 1 'check-constraints: FAIL scripts/gen: language python3 (shebang) not in CONSTRAINTS.md'
plant perl;      printf 'perl -e "print 1"\n' >> "$work/perl/scripts/tool"
want perl 1 'check-constraints: FAIL scripts/tool:5: interpreter perl not in CONSTRAINTS.md'
plant heredoc;   printf 'python3 - <<EOF\nprint(1)\nEOF\n' >> "$work/heredoc/scripts/tool"
want heredoc 1 'check-constraints: FAIL scripts/tool:5: interpreter python3 not in CONSTRAINTS.md'
plant envpre
# shellcheck disable=SC2016  # a literal $( planted into the script
printf 'x=$(TMPDIR=/t python3 f.py)\n' >> "$work/envpre/scripts/tool"
want envpre 1 'check-constraints: FAIL scripts/tool:5: interpreter python3 not in CONSTRAINTS.md'
plant piped;     printf 'git log | ruby -ne 1\n' >> "$work/piped/scripts/tool"
want piped 1 'check-constraints: FAIL scripts/tool:5: interpreter ruby not in CONSTRAINTS.md'
plant dune;      printf '(executable (name t) (libraries mine lwt))\n' >> "$work/dune/src/dune"
want dune 1 'check-constraints: FAIL src/dune: library lwt (ocaml) not in CONSTRAINTS.md'
plant import;    printf 'import { z } from "zod";\n' >> "$work/import/ext/a.mjs"
want import 1 'check-constraints: FAIL ext/a.mjs: library zod (node) not in CONSTRAINTS.md'
plant dep;       printf '{"name": "x", "devDependencies": {"left-pad": "1"}}\n' > "$work/dep/ext/package.json"
want dep 1 'check-constraints: FAIL ext/package.json: library left-pad (node) not in CONSTRAINTS.md'
plant brew;      printf 'brew "fzf"\n' >> "$work/brew/Brewfile"
want brew 1 'check-constraints: FAIL Brewfile:2: library fzf (bash) not in CONSTRAINTS.md'
plant oddext;    printf 'x\n' > "$work/oddext/data.toml"
want oddext 1 'check-constraints: FAIL data.toml: language .toml not in CONSTRAINTS.md'
plant noblock;   printf '# no block here\n' > "$work/noblock/CONSTRAINTS.md"
want noblock 2 'check-constraints: no constraints block in CONSTRAINTS.md'
plant nofile;    rm "$work/nofile/CONSTRAINTS.md"
want nofile 2 'check-constraints: no constraints block in CONSTRAINTS.md'
# rules.4: command positions past reserved words, wrappers and make prefixes
plant ifthen;    printf 'if python3 x; then :; fi\n' >> "$work/ifthen/scripts/tool"
want ifthen 1 'check-constraints: FAIL scripts/tool:5: interpreter python3 not in CONSTRAINTS.md'
plant xargs;     printf 'git ls-files | xargs -0 perl -pi -e 1\n' >> "$work/xargs/scripts/tool"
want xargs 1 'check-constraints: FAIL scripts/tool:5: interpreter perl not in CONSTRAINTS.md'
plant bg;        printf 'git fetch & ruby x\n' >> "$work/bg/scripts/tool"
want bg 1 'check-constraints: FAIL scripts/tool:5: interpreter ruby not in CONSTRAINTS.md'
plant makeat;    printf '\t@python3 x\n' >> "$work/makeat/Makefile"
want makeat 1 'check-constraints: FAIL Makefile:3: interpreter python3 not in CONSTRAINTS.md'
# a language with no shebang runs only where runs-in says (scripts/zt), not here
plant zsh;       printf 'zsh -c true\n' >> "$work/zsh/scripts/tool"
want zsh 1 'check-constraints: FAIL scripts/tool:5: interpreter zsh not in CONSTRAINTS.md'
# deleting one library from the block names its use
plant dropped;   sed 's/ libs unix yojson$/ libs unix/' "$clean/CONSTRAINTS.md" > "$work/dropped/CONSTRAINTS.md"
want dropped 1 'check-constraints: FAIL src/dune: library yojson (ocaml) not in CONSTRAINTS.md'
# the real repo passes its own lint
(cd "$root" && "$lint") > "$work/repo.out" 2>&1 || fail "the repo fails its own lint: $(cat "$work/repo.out")"
checks=$((checks + 1))
echo "check-constraints tests: ok ($checks assertions)"
