// induct-node: one workflow run per ready node, owning the
// node's whole FSM loop (mvp.3). The root worker reads the
// rollup ready set and dispatches one induct-node run per
// ready node, in parallel desks; this run loops one node:
// read state, mint one edge link, spawn one edge worker,
// bind its tape, re-read, until the node rests landed,
// blocked, or deleted, then returns exactly one terminal
// outcome {node, outcome, commit, run_ids, refusals} to
// the root. Landing stays serial at the root: this loop
// takes the land edge only for its own node, one node per
// run, and bp3 re-checks mergeability against the new tip.
// The old node-loop / induct-grade / quest-land steps are
// phases inside this loop (author, grade+verify, land).
// Pi form of the same contract: the root pi session spawns
// one node-worker session per ready node; that session
// claims its node link first, loops spawn_run per edge,
// and returns the same one terminal outcome. Edge workers
// never mint links and never call a second edge.
// Args: {quest, exp, ts, harness, model, desk}.

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
  const refusals = [];
  const runIds = [];
  if (!quest || !exp || !ts) {
    return {
      node: exp || null, outcome: "refused", commit: null,
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

  const links = {};

  function runIdOf(edge, cycle) {
    if (links[edge] && links[edge].run_id) return links[edge].run_id;
    return ts + "-" + edge + "-" + harness + "-" + model +
      "-c" + String(cycle);
  }

  function envPreset() {
    return "BP3_QUEST=" + quest + " BP3_EXP=" + exp + " " + envPrefix;
  }

  function claimNote(edge) {
    const link = links[edge];
    if (!link) return "";
    return (
      "Your first action claims your one-time link: run `" +
      envPrefix + "./bin/bp3 harness link claim " + link.token +
      "` and note the run_id it returns (expected " + link.run_id +
      "). Prefix your state-edge call below with " +
      "BP3_RUN_ID=<that run_id>. "
    );
  }

  // The link minter (mvp.1): this loop, before each edge
  // worker spawns. A refused mint means that worker never
  // starts. The mint names no tape; the launcher binds the
  // worker's session tape after it returns (bindTape).
  async function mintLink(edge, cycle) {
    const cmd =
      envPreset() + "./bin/bp3 harness link mint" +
      " --kind edge --edge " + edge +
      " --graph " + quest + " --node " + exp +
      " --harness " + harness + " --model " + model +
      " --cycle " + String(cycle) +
      (desk ? " --desk " + desk : "");
    const result = await host.agent({
      label: "mint " + exp,
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
    if (!v || v.ok !== true || typeof v.token !== "string" || typeof v.run_id !== "string") {
      refusals.push(
        "link mint refused before the " + edge + " child: " +
        errorText(result)
      );
      return false;
    }
    links[edge] = { token: v.token, run_id: v.run_id };
    runIds.push(v.run_id);
    return true;
  }

  // The named tape binder (followup.3): after the edge
  // worker returns, resolution is mechanical (find-tape on
  // the run-id) and the bind is bind-tape's one row.
  async function bindTape(edge, cycle) {
    const runId = runIdOf(edge, cycle);
    const resolveCmd =
      envPreset() + "./bin/bp3 harness find-tape" +
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
      envPreset() + "./bin/bp3 harness bind-tape" +
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
    const folder = expDir + "/runs/" + runIdOf(edge, cycle);
    return (
      "Your run folder is `" + folder + "` under `" + expDir +
      "/runs/`. " + claimNote(edge) +
      "`BP3_QUEST`, `BP3_EXP`, `BP3_HARNESS`, and `BP3_MODEL` " +
      "arrive via environment; your run-id arrives via the " +
      "claim above and `bp3` stamps it into its verdicts and " +
      "ledger lines. First check whether that concrete run " +
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

  const authorLoad =
    "First load the code-writer skill (read_skill \"code-writer\") " +
    "and follow its procedure, including naming discipline and " +
    "its language references. ";

  async function spawnEdge(edge, state, fix) {
    if (!(await mintLink(edge, state.cycle))) return null;
    let input;
    if (edge === "handoff") {
      input =
        deskNote + "You are the author child for exp `" + exp + "` of quest `" +
        quest + "`, currently in state `todo` at cycle " +
        String(state.cycle) + ". " + authorLoad + tapePreamble(edge, state.cycle) +
        (fix ? " The grader named this fix; carry it verbatim: " + fix : "") +
        " Do the exp's work in the repository, then commit the " +
        "work as a clean git commit and note its full sha. Then " +
        "call the state edge directly yourself: " +
        "`" + envPreset() + "./bin/bp3 q " + quest + " u " + exp +
        " handoff --commit <your-commit-sha> --reason \"<short reason>\"`. " +
        "Children call `bp3 q u` directly; never only return a " +
        "verdict for the parent to relay. Reply with only a JSON " +
        "object {ok, run_id, commit, verdict} where verdict is " +
        "the JSON printed by the handoff call.";
    } else if (edge === "grade" || edge === "verify") {
      const verdicts = edge === "grade" ? "ship|needs_fix" : "pass|fail";
      input =
        deskNote + "You are the " + edge + " child for exp `" + exp + "` of quest `" +
        quest + "`, currently in state `handed_off` at cycle " +
        String(state.cycle) + ". " + tapePreamble(edge, state.cycle) +
        " Judge the exact bound commit " + String(state.commit) +
        "; never edit the work. Then call the state edge directly yourself: " +
        "`" + envPreset() + "./bin/bp3 q " + quest + " u " + exp + " " + edge +
        " --verdict " + verdicts + " --reason \"<short reason>\"`. " +
        "Reply with only a JSON object {ok, run_id, commit, verdict, reason} " +
        "where verdict is the JSON printed by the " + edge + " call and " +
        "reason carries any named fix verbatim.";
    } else {
      input =
        deskNote + "You are the land child for exp `" + exp + "` of quest `" +
        quest + "`, currently in state `approved` at cycle " +
        String(state.cycle) + ". " + tapePreamble(edge, state.cycle) +
        " Call the state edge directly yourself: " +
        "`" + envPreset() + "./bin/bp3 q " + quest + " u " + exp +
        " land --reason \"<short reason>\"`. " +
        "Reply with only a JSON object {ok, run_id, commit, verdict} " +
        "where verdict is the JSON printed by the land call.";
    }
    const result = await host.agent({ label: edge + " " + exp, input });
    const v = parseVerdict(result);
    if (v && typeof v.run_id === "string" && v.run_id) runIds.push(v.run_id);
    await bindTape(edge, state.cycle);
    return v;
  }

  // The FSM loop: one edge worker per iteration, re-reading
  // bp3 after every verdict; this run holds no state of its
  // own across edges. Terminal means landed, blocked, or
  // deleted, and exactly one such outcome returns.
  let fix = "";
  for (let step = 0; step < 12; step++) {
    const state = await readState();
    if (state.state === "unknown") {
      refusals.push("read failed: " + (state.raw || "no verdict"));
      return { node: exp, outcome: "refused", commit: null, run_ids: runIds, refusals };
    }
    if (state.state === "landed" || state.state === "blocked" || state.state === "deleted") {
      return { node: exp, outcome: state.state, commit: state.commit, run_ids: runIds, refusals };
    }
    if (state.state === "todo") {
      await spawnEdge("handoff", state, fix);
      fix = "";
    } else if (state.state === "handed_off") {
      const g = await spawnEdge("grade", state, "");
      const mid = await readState();
      if (mid.state === "handed_off") {
        await spawnEdge("verify", mid, "");
      } else if (g && typeof g.reason === "string" && g.reason) {
        fix = g.reason;
      }
    } else if (state.state === "approved") {
      await spawnEdge("land", state, "");
    } else {
      refusals.push("no phase owns state " + state.state);
      return { node: exp, outcome: "refused", commit: state.commit, run_ids: runIds, refusals };
    }
  }
  refusals.push("FSM loop exceeded 12 edge dispatches without a terminal state");
  const last = await readState();
  return {
    node: exp, outcome: "refused",
    commit: last.commit === undefined ? null : last.commit,
    run_ids: runIds, refusals,
  };
}
