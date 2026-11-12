// induct-exp: loop one exp's inner FSM to landed, blocked, deleted,
// or refused. Installed to .agents/workflows/induct-exp.js by
// `bp3 skills install`. All state moves through `bp3 q u`, called
// directly by the workflow children; this script never writes state.
// Args are supplied by the calling induct skill as {quest, exp, ts};
// ts is a UTC compact timestamp from the caller, embedded by
// children in every run-id because scripts cannot read the clock.

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
        "Run exactly `"+envPrefix+"./bin/bp3 q " + quest + " r " + exp +
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

  function snapshot(s) {
    return s.state + "|" + String(s.commit) + "|c" + String(s.cycle);
  }

  function runFolder(edge, cycle, harnessNote) {
    return (
      expDir + "/runs/" + ts + "-" + edge + "-" + harnessNote +
      "-c" + String(cycle)
    );
  }

  function tapePreamble(edge, cycle) {
    const folder = runFolder(edge, cycle, harness + "-" + model);
    return (
      "Your run folder is `" + folder + "`, where <harness> is the " +
      "value of $BP3_HARNESS (or `unknown` when unset) and <model> " +
      "is the value of $BP3_MODEL (or `unknown` when unset), so " +
      "the concrete folder name is `" + ts + "-" + edge +
      "-<harness>-<model>-c" + String(cycle) + "` under `" +
      expDir + "/runs/`. First check whether that concrete run " +
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

  let before = await readState();
  if (
    before.state === "landed" ||
    before.state === "blocked" ||
    before.state === "deleted"
  ) {
    return { exp: exp, outcome: before.state, run_ids: runIds, refusals: refusals };
  }
  if (before.state === "unknown") {
    refusals.push("initial read failed: " + (before.raw || "no verdict"));
    return { exp: exp, outcome: "refused", run_ids: runIds, refusals: refusals };
  }

  // Bounded stages: todo -> submitted -> approved -> landed is three
  // progress steps; extra headroom covers a needs_fix/fail bounce
  // that still changes state or cycle. No-progress exits at once.
  for (let stage = 0; stage < 8; stage++) {
    let stageResults = [];

    if (before.state === "todo") {
      const author = await host.agent({
        label: "author " + exp,
        input:
          "You are the author child for exp `" + exp + "` of quest `" +
          quest + "`, currently in state `todo` at cycle " +
          String(before.cycle) + ". " + tapePreamble("submit", before.cycle) +
          " Do the exp's work in the repository, then commit the " +
          "work as a clean git commit and note its full sha. Then " +
          "call the state edge directly yourself: " +
          "`"+envPrefix+"./bin/bp3 q " + quest + " u " + exp +
          " submit --commit <your-commit-sha> --reason \"<short reason>\"`. " +
          "Children call `bp3 q u` directly; never only return a " +
          "verdict for the parent to relay. Reply with only a JSON " +
          "object {ok, run_id, commit, verdict} where verdict is " +
          "the JSON printed by the submit call.",
      });
      stageResults = [author];
    } else if (before.state === "submitted") {
      const bound = before.commit ? String(before.commit) : "";
      const reviewPrompt =
        "You are the review child for exp `" + exp + "` of quest `" +
        quest + "`, currently in state `submitted` at cycle " +
        String(before.cycle) + ", bound to commit `" + bound + "`. " +
        tapePreamble("review", before.cycle) +
        " Review the work at the bound commit on its merits and " +
        "judge only; do not edit the work. Then call the state " +
        "edge directly yourself, binding the exact commit: " +
        "`"+envPrefix+"./bin/bp3 q " + quest + " u " + exp +
        " review --verdict ship --commit " + bound +
        " --reason \"<short reason>\"` when the work is correct, " +
        "or the same call with `--verdict needs_fix` when it is " +
        "not. Children call `bp3 q u` directly; never only return " +
        "a verdict for the parent to relay. Reply with only a " +
        "JSON object {ok, run_id, commit, verdict} where verdict " +
        "is the JSON printed by the review call.";
      const checkPrompt =
        "You are the check child for exp `" + exp + "` of quest `" +
        quest + "`, currently in state `submitted` at cycle " +
        String(before.cycle) + ", bound to commit `" + bound + "`. " +
        tapePreamble("check", before.cycle) +
        " Run the exp's checks against the bound commit and judge " +
        "only; do not edit the work. Then call the state edge " +
        "directly yourself, binding the exact commit: " +
        "`"+envPrefix+"./bin/bp3 q " + quest + " u " + exp +
        " check --verdict pass --commit " + bound +
        " --reason \"<short reason>\"` when every check passes, " +
        "or the same call with `--verdict fail` when any check " +
        "fails. Children call `bp3 q u` directly; never only " +
        "return a verdict for the parent to relay. Reply with " +
        "only a JSON object {ok, run_id, commit, verdict} where " +
        "verdict is the JSON printed by the check call.";
      stageResults = await host.parallel([
        { label: "review " + exp, input: reviewPrompt },
        { label: "check " + exp, input: checkPrompt },
      ]);
    } else if (before.state === "approved") {
      const lander = await host.agent({
        label: "land " + exp,
        input:
          "You are the land child for exp `" + exp + "` of quest `" +
          quest + "`, currently in state `approved` at cycle " +
          String(before.cycle) + ". " + tapePreamble("land", before.cycle) +
          " Call the state edge directly yourself: " +
          "`"+envPrefix+"./bin/bp3 q " + quest + " u " + exp +
          " land --reason \"<short reason>\"`. Children call " +
          "`bp3 q u` directly; never only return a verdict for " +
          "the parent to relay. Reply with only a JSON object " +
          "{ok, run_id, commit, verdict} where verdict is the " +
          "JSON printed by the land call.",
      });
      stageResults = [lander];
    } else {
      refusals.push("no stage handles state " + before.state);
      return { exp: exp, outcome: "refused", run_ids: runIds, refusals: refusals };
    }

    for (let i = 0; i < stageResults.length; i++) {
      const v = parseVerdict(stageResults[i]);
      if (v && typeof v.run_id === "string" && v.run_id) {
        runIds.push(v.run_id);
      }
    }

    const after = await readState();
    if (
      after.state === "landed" ||
      after.state === "blocked" ||
      after.state === "deleted"
    ) {
      return { exp: exp, outcome: after.state, run_ids: runIds, refusals: refusals };
    }
    if (snapshot(after) === snapshot(before)) {
      for (let i = 0; i < stageResults.length; i++) {
        refusals.push(errorText(stageResults[i]));
      }
      if (after.state === "unknown") {
        refusals.push("re-read after stage failed: " + (after.raw || "no verdict"));
      }
      return { exp: exp, outcome: "refused", run_ids: runIds, refusals: refusals };
    }
    before = after;
  }

  refusals.push("stage budget exhausted without reaching a terminal state");
  return { exp: exp, outcome: "refused", run_ids: runIds, refusals: refusals };
}
