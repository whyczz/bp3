// bp3g-land: land one approved node, then stop. Installed to
// .agents/workflows/bp3g-land.js by `bp3 skills install`.
// This step owns exactly one transition: it reads state,
// spawns the single land child for an `approved` node, re-reads, and
// returns what the re-read reports. Any other state belongs to
// a different step; this file refuses it untouched. The land
// child calls `bp3 q u` directly; this script never writes
// state. Its one write is proof, not state: as the named
// link minter (mvp.1) it mints the child's one-time link
// via `bp3 harness link mint` before the child spawns; the
// child never writes its own proof.
// Args are supplied by the calling bp3g skill as {quest, node,
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
  const node = rawArgs.node;
  const ts = rawArgs.ts;
  const harness = rawArgs.harness || "muse-code";
  const model = rawArgs.model || "unknown";
  const desk = rawArgs.desk ? String(rawArgs.desk) : "";
  const deskNote = desk ? ("Your working directory is the quest worktree `" + desk + "` - cd there first and run every command from there; do not work in the conductor checkout. ") : "";
  // Mode-aware reads (dogfood.3): a desk exists only in self mode,
  // so desk presence derives the read path - self reads via the
  // desk script, host reads call bp3 on PATH. Never a flag.
  const bp3Bin = desk ? "./bin/bp3" : "bp3";
  const envPrefix =
    "BP3_HARNESS=" + harness + " BP3_MODEL=" + model + " ";
  const refusals = [];
  const runIds = [];
  if (!quest || !node || !ts) {
    return {
      node: node || null,
      outcome: "refused",
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
    void harnessNote;
    return nodeDir + "/runs/" + runIdOf(edge, cycle);
  }

  function envPreset(edge, cycle) {
    // Identity arrives via the claim, never typed env: the
    // child claims its link first and prefixes its edge call
    // with BP3_RUN_ID=<run_id from the claim verdict>; bp3
    // stamps it into verdicts and ledger lines.
    void edge; void cycle;
    return "BP3_QUEST=" + quest + " BP3_NODE=" + node + " " + envPrefix;
  }

  const links = {};

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

  function runIdOf(edge, cycle) {
    if (links[edge] && links[edge].run_id) return links[edge].run_id;
    return ts + "-" + edge + "-" + harness + "-" + model +
      "-c" + String(cycle);
  }

  // The link minter (mvp.1): this launcher, before
  // the child spawns. The child never writes its own proof; a
  // refused write means the child never starts.
  async function mintLink(edge, cycle) {
    const fsm = ["handoff", "grade", "verify", "land", "block", "resume"].includes(edge);
    const cmd =
      envPreset(edge, cycle) + bp3Bin + " harness link mint" +
      (fsm ? " --kind edge --edge " + edge : " --kind node") +
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

  function tapePreamble(edge, cycle) {
    const folder = runFolder(edge, cycle, harness + "-" + model);
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

  const before = await readState();
  if (before.state === "unknown") {
    refusals.push("initial read failed: " + (before.raw || "no verdict"));
    return { node: node, outcome: "refused", run_ids: runIds, refusals: refusals };
  }
  if (before.state !== "approved") {
    refusals.push(
      "expected approved, got " + before.state + "; another step owns that state"
    );
    return { node: node, outcome: "refused", run_ids: runIds, refusals: refusals };
  }

  if (!(await mintLink("land", before.cycle))) {
    return { node: node, outcome: "refused", run_ids: runIds, refusals: refusals };
  }

  const lander = await host.agent({
    label: "land " + node,
    input:
      deskNote + "You are the land child for node `" + node + "` of quest `" +
      quest + "`, currently in state `approved` at cycle " +
      String(before.cycle) + ". " + tapePreamble("land", before.cycle) +
      " Call the state edge directly yourself: " +
      "`" + envPreset("land", before.cycle) + bp3Bin + " q " + quest + " u " + node +
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
    return { node: node, outcome: "landed", run_ids: runIds, refusals: refusals };
  }
  refusals.push(errorText(lander));
  if (after.state === "unknown") {
    refusals.push("re-read after land failed: " + (after.raw || "no verdict"));
  } else {
    refusals.push("land left state " + after.state + ", expected landed");
  }
  return { node: node, outcome: "refused", run_ids: runIds, refusals: refusals };
}
