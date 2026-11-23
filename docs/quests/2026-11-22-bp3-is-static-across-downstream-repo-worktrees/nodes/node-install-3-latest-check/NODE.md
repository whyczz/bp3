---
date: 2026-11-22
quest: ../../QUEST.md
node: install.3
status: proposed
---

# install.3 - latest-check: an installed bp3 says when a newer one is tagged

## TL;DR

One function, `Install.status`, answers "how old am I" for an installed
`bp3-q`: `{version, build, source, source_from, latest_tag,
behind_master, unchecked}`, read from `share/bp3/BUILD` beside the
running executable and from a local bp3 checkout's `v*` tags. That
checkout is `$BP3_REPO_HOME` when set, else the one `share/bp3/SOURCE`
names. When the installed version is older than the latest tag,
`W_INSTALL_BEHIND {installed, latest_tag}` goes where sessions already
look: every `bp3 q`/`n`/`e` verdict's `warnings`, one stdout line from
`bp3 q hooks` on SessionStart (Claude Code adds it to the session's
context), `bp3 config`'s `install` facts, and `bp3 skills check`'s
warnings. When there is no checkout to read, the SessionStart line and
`config` say so instead of going quiet. It never blocks, never
reinstalls, and never touches the network: the check is local only.

## Acceptance gates

Observed today:

```text
$ (in ~/m/predictor) bp3 q r 2026-11-22-predictor-conventions-naming | jq -c .warnings
[]                                          # the install is 64–112 commits behind master; nothing says so
$ bp3 config | jq .install
null
$ echo '{"hook_event_name":"SessionStart"}' | bp3 q hooks     # prints nothing
$ BP3_REPO_HOME=/nope bp3 config | jq .install                # null: no such variable is read
```

Design trace:

```text
(scratch bp3 clone B at 0.2.0; make install PREFIX=$S from B; then in B: scripts/bump minor -> v0.3.0)
(fixture host repo r with one quest q; PATH=$S/bin:$PATH; BP3_REPO_HOME unset)
$ bp3 q r q | jq -c .warnings
["W_INSTALL_BEHIND"]
$ bp3 q r q | jq -c '.warning_facts.W_INSTALL_BEHIND'      # or the repo's existing warning-facts shape
{"installed":"0.2.0","latest_tag":"v0.3.0"}
$ bp3 config | jq -c .install
{"version":"0.2.0","build":"0.2.0+<sha7>","source":"<B>","source_from":"SOURCE","latest_tag":"v0.3.0","behind_master":1,"unchecked":null}
$ echo '{"hook_event_name":"SessionStart",...}' | bp3 q hooks
bp3 0.2.0+<sha7> is installed; v0.3.0 is tagged in <B>: run make install there
$ echo '{"hook_event_name":"PreToolUse",...}' | bp3 q hooks          # no stdout
$ bp3 skills check | jq -c .warnings
["W_INSTALL_BEHIND"]
$ (cd B && make install PREFIX=$S) && bp3 q r q | jq -c .warnings
[]
(BP3_REPO_HOME wins over SOURCE: clone C of B, then in C: scripts/bump patch -> v0.3.1)
$ BP3_REPO_HOME=<C> bp3 q r q | jq -c .warnings
["W_INSTALL_BEHIND"]
$ BP3_REPO_HOME=<C> bp3 config | jq -c '.install | {source, source_from, latest_tag}'
{"source":"<C>","source_from":"BP3_REPO_HOME","latest_tag":"v0.3.1"}
$ BP3_REPO_HOME= bp3 config | jq -r .install.source_from            # empty counts as unset
SOURCE
(no checkout to read)
$ mv B B.gone && bp3 q r q | jq -c .warnings; bp3 config | jq -c '.install | {latest_tag, unchecked}'
[]
{"latest_tag":null,"unchecked":"<B> is not a git checkout"}
$ echo '{"hook_event_name":"SessionStart",...}' | bp3 q hooks
bp3 0.3.0+<sha7> is installed; can't check for a newer one: <B> is not a git checkout (set BP3_REPO_HOME to your bp3 checkout)
$ BP3_REPO_HOME=rel/path bp3 config | jq -r .install.unchecked
BP3_REPO_HOME must be an absolute path: rel/path
(bp3 repo, ./bin/bp3, repo layout)
$ BP3_REPO_HOME=<C> ./bin/bp3 config | jq .install
null
```

```yaml
objective: a downstream session learns its bp3 is behind the latest tag in a local checkout without asking, learns when no checkout can be read, and nothing ever blocks on it or touches the network
prove by:
  - test/install.sh: the trace above in scratch dirs (bp3 clones B and C, a PREFIX, a host fixture repo);
    W_INSTALL_BEHIND on a read and on a write verdict; absent after reinstall at the tag;
    BP3_REPO_HOME at a newer-tagged clone: present, source_from BP3_REPO_HOME; BP3_REPO_HOME empty: as unset;
    no checkout to read (SOURCE's repo gone; BP3_REPO_HOME relative or not a git checkout; no SOURCE and no BP3_REPO_HOME):
    no warning, unchecked names why
  - SessionStart prints exactly one line when behind or unchecked and nothing when current; every other hook event prints nothing
  - repo layout (./bin/bp3 in bp3): install null, no warning, BP3_REPO_HOME ignored
  - unit: Install.compare over versions (behind, equal, ahead, a malformed tag ignored)
  - timing: the median added wall per `bp3 q r` with Install.status on, 20 runs, recorded in the build notes
  - make check-full
done when: each case holds and the warning, config, BP3_REPO_HOME and SessionStart cases fail on master
```

## Diagram

```text
  $BP3_REPO_HOME (absolute, non-empty)  ──wins over──  share/bp3/SOURCE .repo
                                   │
              that local checkout: refs/tags/v*  (and master, for config only)
              share/bp3/BUILD beside the running bp3-q
                                   ▼
                        Install.status (lazy, once per process)
          ┌──────────────┬─────────┴────────┬───────────────────┐
   every verdict     SessionStart hook   bp3 config        bp3 skills check
   warnings[]        one stdout line     install {...}     warnings[]
   (behind only)     (behind or          (always, with
                      unchecked)          unchecked: why)
          │                 │
   conductor reads   session context
          └──► skills.1: the induct report and the check-in report quote it ──► owner
never: block a write, reinstall, call the network
```

## Pseudocode

```python
@lazy
def install_status():
    share = dirname(executable()) / "../share/bp3"
    if not exists(share / "BUILD"):
        return None                                   # repo layout or an old install
    src = json(share / "SOURCE") if exists(share / "SOURCE") else {}   # absent when make install didn't write the share
    env = getenv("BP3_REPO_HOME") or None             # empty counts as unset
    repo, source_from = (env, "BP3_REPO_HOME") if env else (src.get("repo"), "SOURCE" if src else None)
    base = {"version": V, "build": BUILD, "source": repo, "source_from": source_from,
            "latest_tag": None, "behind_master": None, "unchecked": None}
    if repo is None:
        return base | {"unchecked": "no bp3 checkout known"}
    if not isabs(repo):
        return base | {"unchecked": f"BP3_REPO_HOME must be an absolute path: {repo}"}
    if not is_git_repo(repo):
        return base | {"unchecked": f"{repo} is not a git checkout"}
    latest = git(repo, "for-each-ref", "--sort=-v:refname", "--count=1", "--format=%(refname:short)", "refs/tags/v*")
    return base | {"latest_tag": latest or None,
                   "behind_master": lazy(lambda: count_or_none(repo, f"{src.get('commit')}..master"))}  # null if the commit isn't there

def warnings_of(id, is_write):
    s = install_status()
    behind = s and s["latest_tag"] and semver(s["latest_tag"][1:]) > semver(V)
    return existing_warnings(id, is_write) + (["W_INSTALL_BEHIND"] if behind else [])   # unchecked never warns

def hooks(event):
    record(event)                                     # as today
    s = install_status()
    if event != "SessionStart" or not s:
        return
    if behind(s):
        print(f"bp3 {s['build']} is installed; {s['latest_tag']} is tagged in {s['source']}: run make install there")
    elif s["unchecked"]:
        print(f"bp3 {s['build']} is installed; can't check for a newer one: {s['unchecked']} (set BP3_REPO_HOME to your bp3 checkout)")
```

## Tables

| Field | Value |
|---|---|
| Intent | a newer bp3 announces itself to every downstream session, from a local checkout only |
| Lane | standard |
| Output | `src/quest/install.ml` (new: `status`, `compare`), `src/quest/store.ml` (`warnings_of`), `src/quest/hooks.ml` (SessionStart line), `src/quest/main.ml` (`config .install`), `src/quest/names.ml` (`w_install_behind`), `bin/bp3` (`skills check` warnings), `test/install.sh`, unit tests |
| Acceptance | the trace above; fails today (no warning, `install` null, silent hook, `BP3_REPO_HOME` unread) |
| Depends on | install.2 (and through it install.1's `BUILD` and `SOURCE`) |

| Channel | Who sees it | When |
|---|---|---|
| verdict `warnings` | every agent and script reading bp3 JSON | every `bp3 q`/`n`/`e` call, when behind |
| SessionStart stdout | a Claude Code session, as context | once per session, when behind or unchecked, in every repo whose settings run `bp3 q hooks` (predictor and its desks) |
| `bp3 config .install` | anyone asking | on demand; the only place `behind_master` is computed besides the hook |
| `bp3 skills check` warnings | the conductor, before every dispatch (induct) | per dispatch, when behind |
| reports (skills.1) | the owner | the induct report, the check-in report |

| State | Result |
|---|---|
| installed version < latest tag | `W_INSTALL_BEHIND`; SessionStart line |
| equal, or installed ahead (a dev install past the tag) | none; `behind_master` still reported by `config` |
| no tags, a malformed tag | none; `latest_tag` null |
| `BP3_REPO_HOME` set, absolute, non-empty | it wins over `SOURCE`; `source_from: "BP3_REPO_HOME"` |
| `BP3_REPO_HOME=""` | as unset |
| no checkout to read: `SOURCE`'s repo gone, `BP3_REPO_HOME` relative or not a git checkout, no `SOURCE` and no `BP3_REPO_HOME` | no warning; `unchecked` names why; SessionStart prints the can't-check line |
| `SOURCE`'s commit absent from the checkout read | `behind_master` null; the tag check still runs |
| repo layout (bp3's own `_build` engine) | none; `install` null; `BP3_REPO_HOME` ignored |

## Prose

The owner's question was "how are we propagating it?". A warning only in
`bp3 config` reaches nobody: nobody runs `config` to find out something
they don't know to ask. So the warning rides the two channels sessions
already read. Every verdict carries `warnings`, which is how
`W_VERSION_AHEAD` and `W_IDENTITY_UNKNOWN` already reach agents. And the
SessionStart hook runs in every downstream repo that installed bp3's
hooks, desks included, because `.claude/settings.json` is tracked.
Claude Code adds a SessionStart hook's stdout to the session's context
(from its hooks docs, not re-checked this session; dogfood.1 probes it
live). From the agent, skills.1 carries it to the owner by making
conductors quote version warnings in their reports.

It compares against tags, not master. After version.1, master moves past
a tag only by docs commits and by promotions, and every promotion tags.
So "behind the latest tag" is the signal worth an interruption, and
"behind master" is a fact for `config`. A dev install from a quest desk
is ahead of the tag and warns about nothing.

It reads a local checkout and never the network. The owner asked
whether to fetch from GitHub when the local checkout is missing, then
settled it: "let's just have the local bp3 check -> with a BP3_HOME env
var or BP3_REPO_HOME". `SOURCE` names the main checkout by default
(never a desk, so releasing a desk can't orphan it). `BP3_REPO_HOME`
names another one: a moved checkout, an install that `make install`
didn't write (no `SOURCE`), or a scratch clone in a test (dogfood.1
uses it). The name is `BP3_REPO_HOME` rather than `BP3_HOME` because a
`*_HOME` variable conventionally names where a tool is installed
(`JAVA_HOME`, `CARGO_HOME`), which for bp3 is `PREFIX`. It must be
absolute: hooks run from whatever directory the session is in, so a
relative path would point somewhere different in each repo.

When there is nothing to read, the check says so once per session.
Silence there is the blindness this quest fixes. It stays out of verdict
warnings, though, because a missing checkout isn't news on every call.

The cost is one `git for-each-ref` per process, lazily, and only in the
installed layout. The scorecard measures it.

Hooks run on every tool call in a downstream session; only SessionStart
prints, so the check adds one line per session, not per tool call.

## Tests

Known cases: the state table rows, each channel present or absent, the
SessionStart-only output (behind line, can't-check line, nothing),
`BP3_REPO_HOME` winning, empty, relative and not a checkout, repo layout
ignoring it, the source gone. Property-based: `Install.compare` over
generated version pairs agrees with semver order (antisymmetric,
transitive, `v`-prefix and malformed tags ignored).
