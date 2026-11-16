// quest-land: land one approved exp, then stop. Installed to
// .agents/workflows/quest-land.js by `bp3 skills install`.
// This step owns exactly one transition: it reads state,
// spawns the single land child for an `approved` exp, re-reads, and
// returns what the re-read reports. Any other state belongs to
// a different step; this file refuses it untouched. The land
// child calls `bp3 q u` directly; this script never writes
// state. Its one write is proof, not state: as the named
// InitRecord writer (mvp.8) it records the child's InitRecord
// via `bp3 harness record-init` before the child spawns; the
// child never writes its own proof.
// Args are supplied by the calling induct skill as {quest, exp,
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
  const deskNote = desk ? ("Your working directory is the quest worktree `" + desk + "` - cd there first and run every command from there; do not work in the conductor checkout. ") : "";
  const envPrefix =
    "BP3_HARNESS=" + harness + " BP3_MODEL=" + model + " ";
  const refusals = [];
  const runIds = [];
  if (!quest || !exp || !ts) {
    return {
      exp: exp || null,
      outcome: "refused",
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
  // refused write means the child never starts.
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
        "Run exactly `" + cmd + "` from the quest worktree if " +
        "one is named below, else the repository root, and return " +
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
    return { exp: exp, outcome: "refused", run_ids: runIds, refusals: refusals };
  }
  if (before.state !== "approved") {
    refusals.push(
      "expected approved, got " + before.state + "; another step owns that state"
    );
    return { exp: exp, outcome: "refused", run_ids: runIds, refusals: refusals };
  }

  if (!(await recordInit("land", before.cycle))) {
    return { exp: exp, outcome: "refused", run_ids: runIds, refusals: refusals };
  }

  const lander = await host.agent({
    label: "land " + exp,
    input:
      deskNote + "You are the land child for exp `" + exp + "` of quest `" +
      quest + "`, currently in state `approved` at cycle " +
      String(before.cycle) + ". " + tapePreamble("land", before.cycle) +
      " Call the state edge directly yourself: " +
      "`" + envPreset("land", before.cycle) + "./bin/bp3 q " + quest + " u " + exp +
      " land --reason \"<short reason>\"`. Children call " +
      "`bp3 q u` directly; never only return a verdict for " +
      "the parent to relay. Reply with only a JSON object " +
      "{ok, run_id, commit, verdict} where verdict is the " +
      "JSON printed by the land call.",
  });
  const landVerdict = parseVerdict(lander);
  if (landVerdict && typeof landVerdict.run_id === "string" && landVerdict.run_id) {
    runIds.push(landVerdict.run_id);
  }

  const after = await readState();
  if (after.state === "landed") {
    return { exp: exp, outcome: "landed", run_ids: runIds, refusals: refusals };
  }
  refusals.push(errorText(lander));
  if (after.state === "unknown") {
    refusals.push("re-read after land failed: " + (after.raw || "no verdict"));
  } else {
    refusals.push("land left state " + after.state + ", expected landed");
  }
  return { exp: exp, outcome: "refused", run_ids: runIds, refusals: refusals };
}
