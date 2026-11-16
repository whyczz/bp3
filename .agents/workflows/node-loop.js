// node-loop: build one todo exp, then stop. Installed to
// .agents/workflows/node-loop.js by `bp3 skills install`.
// This step owns exactly one transition family: it reads state,
// spawns the single author child for a `todo` exp, re-reads, and
// returns what the re-read reports. Any other state belongs to
// a different step; this file refuses it untouched. All state
// moves through `bp3 q u`, called directly by the author child;
// this script never writes state. Its one write is proof, not
// state: as the named InitRecord writer (mvp.8) it records the
// child's InitRecord via `bp3 harness record-init` before the
// child spawns; the child never writes its own proof. As the
// named tape binder (followup.3) it then binds the child's
// session tape via `bp3 harness bind-tape` after the child
// returns; the child writes no InitRecord, binding, or
// observation.
// Args are supplied by the calling traverse skill as {quest, exp,
// ts, harness, model}; ts is a UTC compact timestamp from the
// caller, embedded by the child in its run-id because scripts
// cannot read the clock.

function textOf(result) {
  if (typeof result === "string") return result;
  if (!result || typeof result !== "object") return "";
  if (typeof result.output === "string") return result.output;
  if (typeof result.text === "string") return result.text;
  if (typeof result.content === "string") return result.content;
  try {
    return JSON.stringify(result);
  } catch (e) {
    return "";
  }
}

function parseVerdict(result) {
  const text = textOf(result);
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (e) {
    // fall through to embedded-JSON extraction
  }
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) {
    try {
      return JSON.parse(text.slice(start, end + 1));
    } catch (e) {
      return null;
    }
  }
  return null;
}

function errorText(result) {
  const v = parseVerdict(result);
  if (v && v.error && v.error.code) {
    const facts = v.error.facts ? JSON.stringify(v.error.facts) : "";
    return v.error.code + (facts ? " " + facts : "");
  }
  const text = textOf(result).trim();
  return text ? text.slice(0, 500) : "no verdict returned";
}

export default async function workflow(host) {
  const rawArgs = typeof host.args === "string"
    ? JSON.parse(host.args)
    : (host.args || {});
  const quest = rawArgs.quest;
  const exp = rawArgs.exp;
  const ts = rawArgs.ts;
  const harness = rawArgs.harness || "muse-code";
  const model = rawArgs.model || "unknown";
  const desk = rawArgs.desk ? String(rawArgs.desk) : "";
  const envPrefix =
    "BP3_HARNESS=" + harness + " BP3_MODEL=" + model + " ";
  const deskNote = desk ? ("Your working directory is the quest worktree `" + desk + "` - cd there first and run every command from there; do not work in the conductor checkout. ") : "";
  const authorLoad =
    "First load the code-writer skill (read_skill \"code-writer\") " +
    "and follow its procedure, including naming discipline and " +
    "its language references. ";
  const refusals = [];
  const runIds = [];
  if (!quest || !exp || !ts) {
    return {
      exp: exp || null,
      outcome: "refused",
      commit: null,
      run_ids: runIds,
      refusals: ["missing quest, exp, or ts in workflow args"],
    };
  }

  const expDir =
    "docs/quests/" + quest + "/experiments/" + exp;

  async function readState() {
    const result = await host.agent({
      label: "read " + exp,
      input:
        "Run exactly `" + envPrefix + "./bin/bp3 q " + quest + " r " + exp +
        "` from the quest worktree if one is named below, else the repository root, and return only its stdout JSON " +
        "verdict verbatim as your entire reply, with no prose and no " +
        "code fences. If the command fails, return its stdout JSON " +
        "verdict verbatim instead. Do not edit any file and do not " +
        "call any `bp3 q u` update edge.",
    });
    const v = parseVerdict(result);
    if (!v || typeof v.state !== "string") {
      return {
        state: "unknown",
        commit: null,
        cycle: 0,
        legal_edges: [],
        raw: textOf(result),
      };
    }
    return {
      state: v.state,
      commit: v.commit === undefined ? null : v.commit,
      cycle: typeof v.cycle === "number" ? v.cycle : 0,
      legal_edges: Array.isArray(v.legal_edges) ? v.legal_edges : [],
      raw: textOf(result),
    };
  }

  function runFolder(edge, cycle, harnessNote) {
    return (
      expDir + "/runs/" + ts + "-" + edge + "-" + harnessNote +
      "-c" + String(cycle)
    );
  }

  function envPreset(edge, cycle) {
    // Env-set identity: BP3_RUN_ID carries the same id as this
    // stage's run folder. `bp3` reads it from the environment
    // and stamps it into verdicts and ledger lines, so no
    // first-command prefix binds the session.
    return (
      "BP3_RUN_ID=" + ts + "-" + edge + "-" + harness + "-" + model +
      "-c" + String(cycle) + " BP3_QUEST=" + quest + " BP3_EXP=" +
      exp + " " + envPrefix
    );
  }

  function runIdOf(edge, cycle) {
    return ts + "-" + edge + "-" + harness + "-" + model +
      "-c" + String(cycle);
  }

  // The named InitRecord writer (mvp.8): this launcher, before
  // the child spawns. The child never writes its own proof; a
  // refused write means the child never starts. The record
  // names no tape (followup.3): the child's session tape does
  // not exist yet, so the launcher binds it after the child
  // returns (bindTape below). The run folder's tape.log stays
  // the child's own transcript, never finish evidence.
  async function recordInit(edge, cycle) {
    const cmd =
      envPreset(edge, cycle) + "./bin/bp3 harness record-init" +
      " --run-id " + runIdOf(edge, cycle) +
      " --harness " + harness + " --quest " + quest +
      " --exp " + exp + " --model " + model +
      (desk ? " --desk " + desk : "");
    const result = await host.agent({
      label: "init " + exp,
      input:
        deskNote +
        "Run exactly `" + cmd + "` from the quest worktree if " +
        "one is named above, else the repository root, and return " +
        "only its stdout JSON verdict verbatim as your entire " +
        "reply, with no prose and no code fences. If the command " +
        "fails, return its stdout JSON verdict verbatim instead. " +
        "Do not edit any file and do not call any `bp3 q u` " +
        "update edge.",
    });
    const v = parseVerdict(result);
    if (!v || v.ok !== true) {
      refusals.push(
        "record-init refused before the " + edge + " child: " +
        errorText(result)
      );
      return false;
    }
    return true;
  }

  // The named tape binder (followup.3): this launcher, after
  // the child returns, when its session tape exists and has
  // closed. Resolution is mechanical — `bp3 harness
  // find-tape` on the run-id — and a resolution that is not
  // unique refuses typed, never a guess; the bind itself is
  // one pointer-only tape_binding row written by bind-tape.
  // The author child writes no binding.
  async function bindTape(edge, cycle) {
    const runId = runIdOf(edge, cycle);
    const resolveCmd =
      envPreset(edge, cycle) + "./bin/bp3 harness find-tape" +
      " --run-id " + runId;
    const resolved = await host.agent({
      label: "resolve " + exp,
      input:
        deskNote +
        "Run exactly `" + resolveCmd + "` from the quest worktree if " +
        "one is named above, else the repository root, and return " +
        "only its stdout JSON verdict verbatim as your entire " +
        "reply, with no prose and no code fences. If the command " +
        "fails, return its stdout JSON verdict verbatim instead. " +
        "Do not edit any file and do not call any `bp3 q u` " +
        "update edge.",
    });
    const rv = parseVerdict(resolved);
    const tapePath = rv && rv.ok === true
      ? (typeof rv.tape_path === "string" && rv.tape_path
         ? rv.tape_path
         : (typeof rv.wal === "string" ? rv.wal : ""))
      : "";
    if (!tapePath) {
      refusals.push(
        "bind-tape resolution refused after the " + edge + " child: " +
        errorText(resolved)
      );
      return false;
    }
    const bindCmd =
      envPreset(edge, cycle) + "./bin/bp3 harness bind-tape" +
      " --run-id " + runId + " --tape-path " + tapePath;
    const bound = await host.agent({
      label: "bind " + exp,
      input:
        deskNote +
        "Run exactly `" + bindCmd + "` from the quest worktree if " +
        "one is named above, else the repository root, and return " +
        "only its stdout JSON verdict verbatim as your entire " +
        "reply, with no prose and no code fences. If the command " +
        "fails, return its stdout JSON verdict verbatim instead. " +
        "Do not edit any file and do not call any `bp3 q u` " +
        "update edge.",
    });
    const bv = parseVerdict(bound);
    if (!bv || bv.ok !== true) {
      refusals.push(
        "bind-tape refused after the " + edge + " child: " +
        errorText(bound)
      );
      return false;
    }
    return true;
  }

  function tapePreamble(edge, cycle) {
    const folder = runFolder(edge, cycle, harness + "-" + model);
    return (
      "Your run folder is `" + folder + "` under `" + expDir +
      "/runs/`. `BP3_RUN_ID`, `BP3_QUEST`, `BP3_EXP`, " +
      "`BP3_HARNESS`, and `BP3_MODEL` arrive via environment " +
      "and `bp3` stamps them into its verdicts and ledger " +
      "lines, so no first-command prefix is needed. First check whether that concrete run " +
      "folder already exists: if it does, stop immediately, do " +
      "not overwrite or reuse it, and return a JSON object " +
      '{"ok":false,"error":{"code":"E_RUN_EXISTS"}} describing ' +
      "the collision. Run-id folders must fail if they already " +
      "exist. Otherwise create the folder, then tee all of your " +
      "session output into its tape.log for the rest of the run: " +
      "run your shell work so stdout and stderr are appended " +
      "through `tee -a <run-folder>/tape.log` (for example " +
      "`exec > >(tee -a <run-folder>/tape.log) 2>&1` in bash, " +
      "or pipe each command through `tee -a`). The tape is " +
      "verbatim evidence only; never parse tape text into facts. " +
      "Write `<run-folder>/notes.md` with brief authored lessons " +
      "from the run before you finish. Record the concrete run " +
      "folder name as run_id in your reply JSON."
    );
  }

  const before = await readState();
  if (before.state === "unknown") {
    refusals.push("initial read failed: " + (before.raw || "no verdict"));
    return { exp: exp, outcome: "refused", commit: null, run_ids: runIds, refusals: refusals };
  }
  if (before.state !== "todo") {
    refusals.push(
      "expected todo, got " + before.state + "; another step owns that state"
    );
    return { exp: exp, outcome: "refused", commit: before.commit, run_ids: runIds, refusals: refusals };
  }

  if (!(await recordInit("handoff", before.cycle))) {
    return { exp: exp, outcome: "refused", commit: before.commit, run_ids: runIds, refusals: refusals };
  }

  const author = await host.agent({
    label: "author " + exp,
    input:
      deskNote + "You are the author child for exp `" + exp + "` of quest `" +
      quest + "`, currently in state `todo` at cycle " +
      String(before.cycle) + ". " + authorLoad + tapePreamble("handoff", before.cycle) +
      " Do the exp's work in the repository, then commit the " +
      "work as a clean git commit and note its full sha. Then " +
      "call the state edge directly yourself: " +
      "`" + envPreset("handoff", before.cycle) + "./bin/bp3 q " + quest + " u " + exp +
      " handoff --commit <your-commit-sha> --reason \"<short reason>\"`. " +
      "Children call `bp3 q u` directly; never only return a " +
      "verdict for the parent to relay. Reply with only a JSON " +
      "object {ok, run_id, commit, verdict} where verdict is " +
      "the JSON printed by the handoff call.",
  });
  const authorVerdict = parseVerdict(author);
  if (authorVerdict && typeof authorVerdict.run_id === "string" && authorVerdict.run_id) {
    runIds.push(authorVerdict.run_id);
  }

  // The child has returned and its session tape has closed:
  // bind it to the Run before re-reading state.
  await bindTape("handoff", before.cycle);

  const after = await readState();
  if (after.state === "handed_off") {
    const commit = after.commit
      ? String(after.commit)
      : (authorVerdict && authorVerdict.commit ? String(authorVerdict.commit) : null);
    return { exp: exp, outcome: "handed_off", commit: commit, run_ids: runIds, refusals: refusals };
  }
  refusals.push(errorText(author));
  if (after.state === "unknown") {
    refusals.push("re-read after author failed: " + (after.raw || "no verdict"));
  } else {
    refusals.push("author left state " + after.state + ", expected handed_off");
  }
  return {
    exp: exp,
    outcome: "refused",
    commit: after.commit === undefined ? null : after.commit,
    run_ids: runIds,
    refusals: refusals,
  };
}
