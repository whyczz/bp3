// bp3g-node: one workflow run per ready node, owning the
// node's whole FSM loop (mvp.3). The root worker reads the
// rollup ready set and dispatches one bp3g-node run per
// ready node, in parallel desks; this run loops one node:
// read state, mint one edge link, spawn one edge worker,
// bind its tape, re-read, until the node rests landed,
// blocked, or deleted, then returns exactly one terminal
// outcome {node, outcome, commit, run_ids, refusals} to
// the root. Landing stays serial at the root: this loop
// takes the land edge only for its own node, one node per
// run, and bp3 re-checks mergeability against the new tip.
// The old node-loop / bp3g-grade / bp3g-land steps are
// phases inside this loop (author, grade+verify, land).
// Pi form of the same contract: the root pi session spawns
// one node-worker session per ready node; that session
// claims its node link first, loops spawn_run per edge,
// and returns the same one terminal outcome. Edge workers
// never mint links and never call a second edge.
// Fail-fast (mvp.5): failure is a state transition, never a
// waiting process. An edge worker completes its edge,
// returns a typed failure, or dies. A typed failure makes
// this loop record the decision point through the block
// edge once — with the failure's reason verbatim — and
// exit; it never retries the failed edge, parks, polls
// for the human, or pages anyone (paging is the root
// worker's job, off the blocked bubble). A worker that
// dies with no parseable verdict is an orphaned Run: the
// node is not blocked, and the next loop iteration mints
// one fresh link and dispatches one replacement. The
// terminal bubble carries facts only — quest, node,
// state, reason, last edge, claim/run chain, desk, and
// inbox key — so revival after resume is a fresh run
// that re-reads bp3; no pid or session is ever resumed.
// Pure-grade (followup.5): grade/verify workers return
// verdicts as data and cast nothing; this loop (the looper)
// applies the combined verdict with exactly one cast
// (`grade --verdict ... --verify-verdict ...`), opens the
// fix-ledger entry, and dispatches the author with the fix
// verbatim. Named pushbacks (superseded, empty fix, blocked)
// escalate by name before any cast; a named mechanical fix
// casts `--mechanical` and never blocks, and the cycle cap
// counts disagreement cycles only. The author records the
// ledger entry RESOLVED in its fix commit.
// Args: {quest, node, ts, harness, model, desk, context}.
// The conductor's context (a cycle's named fix, carried
// verbatim) rides the first author cycle; a grade's own
// named fix replaces it on later cycles. Context is never
// dropped silently: with none supplied, no clause is added.

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
  const node = rawArgs.node;
  const ts = rawArgs.ts;
  const harness = rawArgs.harness || "muse-code";
  const model = rawArgs.model || "unknown";
  const desk = rawArgs.desk ? String(rawArgs.desk) : "";
  const context = rawArgs.context ? String(rawArgs.context) : "";
  const envPrefix =
    "BP3_HARNESS=" + harness + " BP3_MODEL=" + model + " ";
  const deskNote = desk ? ("Your working directory is the quest worktree `" + desk + "` - cd there first and run every command from there; do not work in the conductor checkout. ") : "";
  // Mode-aware reads (dogfood.3): a desk exists only in self mode,
  // so desk presence derives the read path - self reads via the
  // desk script, host reads call bp3 on PATH. Never a flag.
  const bp3Bin = desk ? "./bin/bp3" : "bp3";
  const refusals = [];
  const runIds = [];
  if (!quest || !node || !ts) {
    return {
      node: node || null, outcome: "refused", commit: null,
      run_ids: runIds,
      refusals: ["missing quest, node, or ts in workflow args"],
    };
  }

  const nodeDir =
    "docs/quests/" + quest + "/nodes/" + node;

  async function readState() {
    const result = await host.agent({
      label: "read " + node,
      input:
        deskNote +
        "Run exactly `" + envPrefix + bp3Bin + " q " + quest + " r " + node +
        "` from the quest worktree if one is named above, else the repository root, and return only its stdout JSON " +
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
        reason: null,
        raw: textOf(result),
      };
    }
    return {
      state: v.state,
      commit: v.commit === undefined ? null : v.commit,
      cycle: typeof v.cycle === "number" ? v.cycle : 0,
      legal_edges: Array.isArray(v.legal_edges) ? v.legal_edges : [],
      // The recorded decision point (mvp.5): present on a
      // blocked node's own read, so a fresh worker — or a
      // revived root — reconstructs why it stopped from
      // bp3 alone.
      reason: (v.blocked && typeof v.blocked.reason === "string" && v.blocked.reason)
        ? v.blocked.reason
        : (typeof v.blocked_reason === "string" && v.blocked_reason ? v.blocked_reason : null),
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
    return "BP3_QUEST=" + quest + " BP3_NODE=" + node + " " + envPrefix;
  }

  function claimNote(edge) {
    const link = links[edge];
    if (!link) return "";
    return (
      "Your first action claims your one-time link: run `" +
      envPrefix + bp3Bin + " harness link claim " + link.token +
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
      envPreset() + bp3Bin + " harness link mint" +
      " --kind edge --edge " + edge +
      " --quest " + quest + " --node " + node +
      " --harness " + harness + " --model " + model +
      " --cycle " + String(cycle) +
      (desk ? " --desk " + desk : "");
    const result = await host.agent({
      label: "mint " + node,
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
      envPreset() + bp3Bin + " harness find-tape" +
      " --run-id " + runId;
    const resolved = await host.agent({
      label: "resolve " + node,
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
      envPreset() + bp3Bin + " harness bind-tape" +
      " --run-id " + runId + " --tape-path " + tapePath;
    const bound = await host.agent({
      label: "bind " + node,
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

  // Fail-fast classification (mvp.5). Three shapes come
  // back from an edge worker: a verdict was cast (bp3
  // state moved, or will be seen moved on re-read), a
  // typed failure (a parseable refusal — the child's own
  // ok:false, or the bp3 verdict it relayed), or silence
  // (no parseable verdict at all: the worker died, and
  // its Run is derived orphaned by the supervisor fold).
  function classify(v) {
    if (!v) return { kind: "orphaned" };
    const inner = (v.verdict && typeof v.verdict === "object") ? v.verdict : null;
    if (v.ok === false || (inner && inner.ok === false)) {
      return { kind: "typed", reason: failureReason(v, inner) };
    }
    return { kind: "cast" };
  }

  function failureReason(v, inner) {
    if (typeof v.reason === "string" && v.reason) return v.reason;
    const err = (inner && inner.error) || v.error || null;
    if (err) {
      if (typeof err.guidance === "string" && err.guidance) return err.guidance;
      if (typeof err.code === "string" && err.code) return err.code;
    }
    return "edge worker returned a typed failure with no reason";
  }

  // The one terminal bubble (mvp.5): facts only, never a
  // live handle. The root worker pages the human off a
  // blocked bubble's reason and inbox key, and revives
  // the node after resume by minting a fresh node link —
  // nothing here is resumed in place.
  function bubble(state, commit, reason, lastEdge) {
    return {
      quest: quest,
      node: node,
      outcome: state,
      commit: commit === undefined ? null : commit,
      reason: reason || null,
      last_edge: lastEdge || null,
      run_ids: runIds,
      ledger: fixLedger,
      desk: desk || null,
      inbox_key: quest + "/" + node,
      refusals,
    };
  }

  // The block edge is this loop's own call (mvp.5), taken
  // exactly once for a typed failure, after the failed
  // worker's tape bind above has reaped its Run: every
  // edge Run this loop spawned is terminal in bp3 before
  // the node worker exits on blocked. The reason rides
  // verbatim; dirty work is checkpointed by bp3 only
  // when the tree is dirty at this moment.
  async function callBlock(reason) {
    const safe = String(reason).replace(/(["$`\\])/g, "\\$1");
    const cmd =
      envPreset() + bp3Bin + " q " + quest + " u " + node +
      " block --reason \"" + safe + "\"";
    const result = await host.agent({
      label: "block " + node,
      input:
        deskNote +
        "Run exactly `" + cmd + "` from the quest worktree if " +
        "one is named above, else the repository root, and return " +
        "only its stdout JSON verdict verbatim as your entire " +
        "reply, with no prose and no code fences. If the command " +
        "fails, return its stdout JSON verdict verbatim instead. " +
        "Do not edit any file.",
    });
    return parseVerdict(result);
  }

  // Record the decision point and exit: one block call,
  // one re-read, one blocked bubble. A block refused
  // because the node already rests blocked (a race with
  // the cycle cap) still exits blocked — the re-read is
  // the judge, never this loop's memory.
  async function blockAndExit(reason, lastEdge, commit) {
    const bv = await callBlock(reason);
    const after = await readState();
    if (after.state === "blocked") {
      return bubble("blocked", after.commit, after.reason || reason, lastEdge);
    }
    if (bv && bv.ok === true && typeof bv.state === "string") {
      return bubble(bv.state, commit, reason, lastEdge);
    }
    refusals.push(
      "block refused after " + lastEdge + " failure: " +
      (bv ? errorText(JSON.stringify(bv)) : "no verdict returned") +
      "; re-read shows " + after.state
    );
    return {
      node: node, outcome: "refused",
      commit: after.commit === undefined ? null : after.commit,
      run_ids: runIds, refusals,
    };
  }

  function tapePreamble(edge, cycle) {
    const folder = nodeDir + "/runs/" + runIdOf(edge, cycle);
    return (
      "Your run folder is `" + folder + "` under `" + nodeDir +
      "/runs/`. " + claimNote(edge) +
      "`BP3_QUEST`, `BP3_NODE`, `BP3_HARNESS`, and `BP3_MODEL` " +
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
        deskNote + "You are the author child for node `" + node + "` of quest `" +
        quest + "`, currently in state `todo` at cycle " +
        String(state.cycle) + ". " + authorLoad + tapePreamble(edge, state.cycle) +
        (fix ? " The grader named this fix; carry it verbatim: " + fix +
          " Record this fix-ledger entry as RESOLVED in your run " +
          "folder's notes.md as part of your fix commit." : "") +
        " Do the node's work in the repository, then commit the " +
        "work as a clean git commit and note its full sha. Then " +
        "call the state edge directly yourself: " +
        "`" + envPreset() + bp3Bin + " q " + quest + " u " + node +
        " handoff --commit <your-commit-sha> --reason \"<short reason>\"`. " +
        "Children call `bp3 q u` directly; never only return a " +
        "verdict for the parent to relay. Reply with only a JSON " +
        "object {ok, run_id, commit, verdict} where verdict is " +
        "the JSON printed by the handoff call.";
    } else if (edge === "grade" || edge === "verify") {
      const verdicts = edge === "grade" ? "ship|needs_fix" : "pass|fail";
      input =
        deskNote + "You are the " + edge + " child for node `" + node + "` of quest `" +
        quest + "`, currently in state `handed_off` at cycle " +
        String(state.cycle) + ". " + tapePreamble(edge, state.cycle) +
        " Judge the exact bound commit " + String(state.commit) +
        "; never edit the work and do not call any `bp3 q u` update edge. " +
        "Pure grade (followup.5): return your verdict as data for the " +
        "looper to apply. Reply with only a JSON object {ok, run_id, " +
        "commit, verdict, fix, fix_class, failed_rows} where verdict is " +
        verdicts + ", fix carries any named fix verbatim, and reason " +
        "is accepted as the fix for older replies.";
    } else {
      input =
        deskNote + "You are the land child for node `" + node + "` of quest `" +
        quest + "`, currently in state `approved` at cycle " +
        String(state.cycle) + ". " + tapePreamble(edge, state.cycle) +
        " Call the state edge directly yourself: " +
        "`" + envPreset() + bp3Bin + " q " + quest + " u " + node +
        " land --reason \"<short reason>\"`. " +
        "Reply with only a JSON object {ok, run_id, commit, verdict} " +
        "where verdict is the JSON printed by the land call.";
    }
    const result = await host.agent({ label: edge + " " + node, input });
    const v = parseVerdict(result);
    if (v && typeof v.run_id === "string" && v.run_id) runIds.push(v.run_id);
    await bindTape(edge, state.cycle);
    return v;
  }

  // The looper's one cast (followup.5): grade and verify
  // replies are data; this loop combines them and casts once.
  function pureVerdict(v, positive, negative) {
    if (!v) return negative;
    const raw = typeof v.verdict === "string" ? v.verdict
      : typeof v.outcome === "string" ? v.outcome : null;
    if (raw === positive || raw === negative) return raw;
    if (v.ok === false) return negative;
    return positive;
  }
  function pureFix(v) {
    if (!v) return "";
    if (typeof v.fix === "string" && v.fix) return v.fix;
    if (typeof v.reason === "string" && v.reason) return v.reason;
    return "";
  }
  const fixLedger = [];
  async function callApply(combined, state) {
    const castVerdict = combined.outcome === "ship" ? "ship" : "needs_fix";
    const reasonText = combined.outcome === "ship"
      ? "grade ship; verify " + combined.verify_verdict : combined.fix;
    const safe = String(reasonText).replace(/(["$`\\])/g, "\\$1");
    const cmd =
      envPreset() + bp3Bin + " q " + quest + " u " + node +
      " grade --verdict " + castVerdict + " --commit " + String(state.commit) +
      " --verify-verdict " + combined.verify_verdict +
      (combined.fix_class === "mechanical" ? " --mechanical" : "") +
      " --reason \"" + safe + "\"";
    const result = await host.agent({
      label: "apply " + node,
      input:
        deskNote +
        "Run exactly `" + cmd + "` from the quest worktree if " +
        "one is named above, else the repository root, and return " +
        "only its stdout JSON verdict verbatim as your entire " +
        "reply, with no prose and no code fences. If the command " +
        "fails, return its stdout JSON verdict verbatim instead. " +
        "Do not edit any file.",
    });
    return parseVerdict(result);
  }

  // The FSM loop: one edge worker per iteration, re-reading
  // bp3 after every verdict; this run holds no state of its
  // own across edges. Terminal means landed, blocked, or
  // deleted, and exactly one such bubble returns. Fail-fast
  // (mvp.5): a typed failure blocks at once through this
  // loop's own block call; an orphaned worker is replaced
  // by the next iteration's fresh link; neither path ever
  // waits on a human inside this run.
  let fix = context;
  let lastEdge = null;
  for (let step = 0; step < 12; step++) {
    const state = await readState();
    if (state.state === "unknown") {
      refusals.push("read failed: " + (state.raw || "no verdict"));
      return { node: node, outcome: "refused", commit: null, run_ids: runIds, refusals };
    }
    if (state.state === "landed" || state.state === "blocked" || state.state === "deleted") {
      return bubble(state.state, state.commit,
        state.state === "blocked" ? (state.reason || fix) : null, lastEdge);
    }
    if (state.state === "todo") {
      lastEdge = "handoff";
      const r = await spawnEdge("handoff", state, fix);
      fix = "";
      const c = classify(r);
      if (c.kind === "typed") return blockAndExit(c.reason, "handoff", state.commit);
      if (c.kind === "orphaned") {
        refusals.push(
          "handoff worker orphaned (no verdict); next loop mints a replacement link");
      }
    } else if (state.state === "handed_off") {
      lastEdge = "grade";
      const g = await spawnEdge("grade", state, "");
      const gc = classify(g);
      if (gc.kind === "typed") return blockAndExit(gc.reason, "grade", state.commit);
      if (gc.kind === "orphaned") {
        refusals.push(
          "grade worker orphaned (no verdict); next loop mints a replacement link");
        continue;
      }
      lastEdge = "verify";
      const vf = await spawnEdge("verify", state, "");
      const vc = classify(vf);
      if (vc.kind === "typed") return blockAndExit(vc.reason, "verify", state.commit);
      if (vc.kind === "orphaned") {
        refusals.push(
          "verify worker orphaned (no verdict); next loop mints a replacement link");
        continue;
      }
      // Pure verdicts in; one looper cast out (followup.5).
      const combined = {
        outcome:
          pureVerdict(g, "ship", "needs_fix") === "ship" &&
          pureVerdict(vf, "pass", "fail") === "pass" ? "ship" : "needs_fix",
        verify_verdict: pureVerdict(vf, "pass", "fail"),
        fix: pureFix(g) || pureFix(vf),
        fix_class: g && typeof g.fix_class === "string" ? g.fix_class : "standard",
      };
      if (combined.outcome === "needs_fix" && !combined.fix.trim()) {
        return blockAndExit(
          "empty fix: needs_fix verdict carried no fix text; no author dispatched",
          "grade", state.commit);
      }
      if (combined.outcome === "needs_fix") {
        fixLedger.push({ state: "OPEN", fix: combined.fix, commit: state.commit, cycle: state.cycle });
        fix = combined.fix;
      }
      lastEdge = "grade";
      const applied = await callApply(combined, state);
      if (!applied || applied.ok !== true) {
        refusals.push("looper cast refused: " +
          (applied ? errorText(JSON.stringify(applied)) : "no verdict returned"));
      }
    } else if (state.state === "approved") {
      lastEdge = "land";
      const r = await spawnEdge("land", state, "");
      const c = classify(r);
      if (c.kind === "typed") return blockAndExit(c.reason, "land", state.commit);
      if (c.kind === "orphaned") {
        refusals.push(
          "land worker orphaned (no verdict); next loop mints a replacement link");
      }
    } else {
      refusals.push("no phase owns state " + state.state);
      return { node: node, outcome: "refused", commit: state.commit, run_ids: runIds, refusals };
    }
  }
  refusals.push("FSM loop exceeded 12 edge dispatches without a terminal state");
  const last = await readState();
  return {
    node: node, outcome: "refused",
    commit: last.commit === undefined ? null : last.commit,
    run_ids: runIds, refusals,
  };
}
