// induct-exp: build one todo exp, then stop. Installed to
// .agents/workflows/induct-exp.js by `bp3 skills install`.
// This step owns exactly one transition family: it reads state
// once, spawns the single author child for a `todo` exp, and
// returns what the re-read reports. Any other state belongs to
// a different step; this file refuses it untouched. All state
// moves through `bp3 q u`, called directly by the author child;
// this script never writes state.
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
  const envPrefix =
    "BP3_HARNESS=" + harness + " BP3_MODEL=" + model + " ";
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
        "` from the repository root and return only its stdout JSON " +
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
    // Per-stage witnessed binding: BP3_RUN_ID carries the same id
    // as this stage's run folder. Hooks cannot inherit env from a
    // child, but PreToolUse payloads carry the full command text,
    // so the first prefixed command binds session -> run.
    return (
      "BP3_RUN_ID=" + ts + "-" + edge + "-" + harness + "-" + model +
      "-c" + String(cycle) + " BP3_QUEST=" + quest + " BP3_EXP=" +
      exp + " " + envPrefix
    );
  }

  function tapePreamble(edge, cycle) {
    const folder = runFolder(edge, cycle, harness + "-" + model);
    return (
      "Your run folder is `" + folder + "` under `" + expDir +
      "/runs/`. Prefix your FIRST shell command with `" +
      envPreset(edge, cycle) + "` (hooks witness this prefix " +
      "to bind your session to this run). First check whether that concrete run " +
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

  const author = await host.agent({
    label: "author " + exp,
    input:
      "You are the author child for exp `" + exp + "` of quest `" +
      quest + "`, currently in state `todo` at cycle " +
      String(before.cycle) + ". " + authorLoad + tapePreamble("submit", before.cycle) +
      " Do the exp's work in the repository, then commit the " +
      "work as a clean git commit and note its full sha. Then " +
      "call the state edge directly yourself: " +
      "`" + envPreset("submit", before.cycle) + "./bin/bp3 q " + quest + " u " + exp +
      " submit --commit <your-commit-sha> --reason \"<short reason>\"`. " +
      "Children call `bp3 q u` directly; never only return a " +
      "verdict for the parent to relay. Reply with only a JSON " +
      "object {ok, run_id, commit, verdict} where verdict is " +
      "the JSON printed by the submit call.",
  });
  const authorVerdict = parseVerdict(author);
  if (authorVerdict && typeof authorVerdict.run_id === "string" && authorVerdict.run_id) {
    runIds.push(authorVerdict.run_id);
  }

  const after = await readState();
  if (after.state === "submitted") {
    const commit = after.commit
      ? String(after.commit)
      : (authorVerdict && authorVerdict.commit ? String(authorVerdict.commit) : null);
    return { exp: exp, outcome: "submitted", commit: commit, run_ids: runIds, refusals: refusals };
  }
  refusals.push(errorText(author));
  if (after.state === "unknown") {
    refusals.push("re-read after author failed: " + (after.raw || "no verdict"));
  } else {
    refusals.push("author left state " + after.state + ", expected submitted");
  }
  return {
    exp: exp,
    outcome: "refused",
    commit: after.commit === undefined ? null : after.commit,
    run_ids: runIds,
    refusals: refusals,
  };
}
