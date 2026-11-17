// bp3g-grade: judge one handed_off node on its bound commit.
// Installed to .agents/workflows/bp3g-grade.js by
// `bp3 skills install`. The grade climbs the evidence ladder
// (mvp.7): records, diff, tests run, style, then tape via
// derivation pointers (find-tape --entry); the whole tape is
// escalation only, blocked/confused/lying and named.
// Grade validations (followup.1): before the audit child
// spawns, a deterministic validations pipeline mints every
// adherence row in code (one plug per row, ctx in, one typed
// evidence row out; silence can be the expectation and empty
// stdout is quoted with the machine-minted token below, never
// hand-quoted by an LLM). The audit child then builds only
// acceptance rows. A row without typed evidence is an
// audit-internal re-collect (one retry, named rows), never an
// FSM verdict: it burns no author cycle and pages no human.
// Evidence still uncollectable returns outcome
// `audit_failure`, naming the row and the collection error,
// with no grade/verify cast. Grade and verify children then
// run in parallel on the exact bound commit and call their
// verdict edges directly; a cast refused with E_ILLEGAL_EDGE
// after its sibling moved state is a named expected verdict
// race, not an unexplained refusal. Grade children never
// edit the work. As the link minter (mvp.1) this launcher
// mints each child's one-time link via `bp3 harness link
// mint` before that child spawns; no child writes its own
// proof. Returns {outcome, matrix, run_ids, refusals};
// replay on the same commit is safe: the audit is read-only
// and re-cast verdicts bind the same commit.
// Args are supplied by the calling bp3g skill as
// {graph, node, ts, harness, model, commit}; ts is a UTC compact
// timestamp from the caller, embedded by children in every
// run-id because scripts cannot read the clock.

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

const EVIDENCE_KINDS = ["file", "command", "ledger", "grep"];

function typedEvidence(ev) {
  return (
    !!ev &&
    typeof ev === "object" &&
    EVIDENCE_KINDS.indexOf(ev.kind) >= 0 &&
    typeof ev.ref === "string" && ev.ref !== "" &&
    typeof ev.quote === "string" && ev.quote !== ""
  );
}

// Machine-minted quote for command output (followup.1): an
// empty stdout is evidence when silence is the expectation,
// quoted with this token by code, never hand-quoted as "".
function quoteForStdout(stdout, exit) {
  const out = typeof stdout === "string" ? stdout : "";
  if (out !== "") return out;
  return "(empty stdout, exit " + String(exit) + ")";
}

function stdoutOf(obs) {
  return obs && typeof obs.stdout === "string" ? obs.stdout : "";
}

function exitOf(obs) {
  return obs && typeof obs.exit === "number" ? obs.exit : 1;
}

// Grade validations (followup.1, owner-locked names): each
// plug is deterministic code — ctx in, one typed evidence
// row out, expectation declared in the plug itself. ctx is
// {nodeDir, commit, obs} where obs carries raw command output
// gathered verbatim; plugs judge, transports never quote.
function validate_git_clean(ctx) {
  const stdout = stdoutOf(ctx.obs.git_clean);
  const exit = exitOf(ctx.obs.git_clean);
  const ok = exit === 0 && stdout === "";
  return {
    case: "adherence: no hand-edited state",
    rung: "2",
    evidence: { kind: "command", ref: "git status --porcelain", quote: quoteForStdout(stdout, exit) },
    verdict: ok ? "pass" : "fail",
  };
}

function validate_clean_commit(ctx) {
  const stdout = stdoutOf(ctx.obs.git_show);
  const exit = exitOf(ctx.obs.git_show);
  const shown = exit === 0 && stdout.indexOf(ctx.commit) >= 0;
  const clean = validate_git_clean(ctx).verdict === "pass";
  const first = stdout.split("\n")[0] || "";
  return {
    case: "adherence: clean commit",
    rung: "2",
    evidence: { kind: "command", ref: "git show " + ctx.commit, quote: quoteForStdout(first, exit) },
    verdict: shown && clean ? "pass" : "fail",
  };
}

// Run-folder lines arrive from one shell one-liner as canonical
// `<folder> tape=yes|no notes=yes|no` lines. A transport may
// still carry prose-shaped lines, so presence is read
// tolerantly: only affirmed presence counts, and an affirmed
// absence (missing, =no) never passes.
function folderLines(raw) {
  const parts = Array.isArray(raw) ? raw
    : typeof raw === "string" ? raw.split(/\r?\n/) : [];
  return parts.filter(function (l) {
    return typeof l === "string" && l.trim() !== "";
  }).map(function (l) { return l.trim(); });
}

function lineHasFile(line, stem) {
  const s = String(line).toLowerCase();
  const eq = s.match(new RegExp(stem + "\\s*=\\s*(yes|no)\\b"));
  if (eq) return eq[1] === "yes";
  if (new RegExp("(missing|absent|without|no)\\b[^,;]{0,40}" + stem + "\\b").test(s)) return false;
  if (new RegExp(stem + "\\b[^,;]{0,40}\\b(missing|absent|not present|not found)\\b").test(s)) return false;
  if (new RegExp(stem + "(?:\\.\\w+)?\\b[^,;]{0,40}\\b(present|exists|found|yes)\\b").test(s)) return true;
  return new RegExp(stem + "(?:\\.log|\\.md)?\\b").test(s);
}

function validate_run_folder_present(ctx) {
  const lines = folderLines(ctx.obs.run_folders);
  const complete = lines.filter(function (l) {
    return lineHasFile(l, "tape") && lineHasFile(l, "notes");
  });
  const handoff = complete.filter(function (l) { return l.indexOf("-handoff-") >= 0; });
  const chosen = handoff[0] || complete[0] || "";
  return {
    case: "adherence: run folder present",
    rung: "2",
    evidence: {
      kind: "file",
      ref: ctx.nodeDir + "/runs/",
      quote: chosen !== "" ? chosen : "no run folder with tape.log and notes.md",
    },
    verdict: chosen !== "" ? "pass" : "fail",
  };
}

function validate_handoff_by_child(ctx) {
  const line = typeof ctx.obs.handoff_line === "string" ? ctx.obs.handoff_line : "";
  const ok = line.indexOf('"edge":"handoff"') >= 0 || line.indexOf('"edge":"submit"') >= 0;
  return {
    case: "adherence: handoff by child",
    rung: "2",
    evidence: {
      kind: "ledger",
      ref: ctx.nodeDir + "/ledger.jsonl handoff line",
      quote: line !== "" ? line : "(no handoff ledger line)",
    },
    verdict: ok ? "pass" : "fail",
  };
}

function validate_env_run_id_stamped(ctx) {
  const line = typeof ctx.obs.handoff_line === "string" ? ctx.obs.handoff_line : "";
  const ok = /"run_id":"[^"]+"/.test(line);
  return {
    case: "adherence: env run-id stamped",
    rung: "2",
    evidence: {
      kind: "ledger",
      ref: ctx.nodeDir + "/ledger.jsonl handoff line",
      quote: line !== "" ? line : "(no handoff ledger line)",
    },
    verdict: ok ? "pass" : "fail",
  };
}

const GRADE_VALIDATIONS = [
  validate_git_clean,
  validate_clean_commit,
  validate_run_folder_present,
  validate_handoff_by_child,
  validate_env_run_id_stamped,
];

function runValidations(ctx) {
  return GRADE_VALIDATIONS.map(function (v) { return v(ctx); });
}

function rowCase(row, i) {
  return row && typeof row.case === "string" && row.case !== ""
    ? row.case
    : "row " + String(i + 1);
}

// Rows the audit still owes typed evidence for. Any verdict
// label on an untyped row is paperwork, not a judgment.
function untypedRows(rows) {
  if (!Array.isArray(rows)) return [];
  const out = [];
  rows.forEach(function (row, i) {
    if (!typedEvidence(row ? row.evidence : null)) out.push(rowCase(row, i));
  });
  return out;
}

// Deferred is a disposition, not a failure: the node's own
// text defers the case to a named owning node and the row's
// evidence is that deferral text. A deferral naming no owner
// is no deferral at all.
function deferralNamesOwner(text) {
  return /defer/i.test(text) && /\bnode[\s-]*\d+\b/i.test(text);
}

// The evidence ladder (GOAL.md contract, mvp.7), in order;
// each rung only when the ones above leave the verdict
// undecided. Rung 5 splits: 5a resolves derivation pointers
// one entry at a time, 5b reads the whole tape and is
// escalation only.
const LADDER_RUNGS = ["1", "2", "3", "4", "5a", "5b"];
const LADDER_TEXT =
  "Climb the evidence ladder in order, each rung only when " +
  "the ones above leave the verdict undecided: rung 1 the " +
  "graph and node records (what was asked); rung 2 committed " +
  "code and git diff at the exact commit; rung 3 demos and " +
  "tests, run — not read about; rung 4 style " +
  "(code-writer/code-reviewer discipline); rung 5a tape via " +
  "derivation pointers first: resolve each pointer with " +
  "`bp3 harness find-tape --run-id <run-id> --entry " +
  "<entry-id>` (digest-verified; --before-entries/" +
  "--after-entries widen only for context) and cite the " +
  "pointer in the row; rung 5b the whole tape, escalation " +
  "only when blocked, confused, or lying, and named in the " +
  "verdict. A grade decided at rungs 1-4 shows zero " +
  "whole-log reads in its matrix; defaulting to rung 5 is " +
  "not a grade. ";

function rungOf(row) {
  if (!row || row.rung === undefined || row.rung === null) return null;
  const rung = String(row.rung);
  return LADDER_RUNGS.indexOf(rung) >= 0 ? rung : null;
}

// Whole-tape escalation is allowed only when it names its
// reason, like a deferral names its owner: a rung 5b row
// naming none of blocked/confused/lying is no evidence.
function escalationNamesReason(text) {
  return /\b(blocked|confused|lying)\b/i.test(text);
}

// A row without typed evidence never carries pass or
// deferred; a verdict outside pass|fail|missing|deferred is
// no verdict at all. Row order never changes the outcome
// (outcomeFor only asks `some` over gated rows).
function normalizeRow(row, i) {
  const name =
    row && typeof row.case === "string" && row.case !== ""
      ? row.case
      : "row " + String(i + 1);
  let verdict =
    row && ["pass", "fail", "missing", "deferred"].indexOf(row.verdict) >= 0
      ? row.verdict
      : "missing";
  let evidence = row ? row.evidence : null;
  if (!typedEvidence(evidence)) {
    if (verdict === "pass" || verdict === "deferred") verdict = "missing";
    evidence = {
      kind: "command",
      ref: "evidence audit",
      quote: "row carried no typed evidence",
    };
  } else {
    evidence = { kind: evidence.kind, ref: evidence.ref, quote: evidence.quote };
    if (verdict === "deferred" && !deferralNamesOwner(name + " " + evidence.quote)) {
      verdict = "missing";
    } else if (verdict === "missing" && deferralNamesOwner(name + " " + evidence.quote)) {
      // The deferral text itself is the disposition, whatever
      // label the audit put on the row.
      verdict = "deferred";
    }
  }
  const rung = rungOf(row);
  if (
    rung === "5b" &&
    (verdict === "pass" || verdict === "deferred") &&
    !escalationNamesReason(name + " " + evidence.quote)
  ) {
    // An unnamed whole-tape read never carries a grade.
    verdict = "missing";
  }
  return { case: name, evidence: evidence, verdict: verdict, rung: rung };
}

function normalizeMatrix(raw) {
  if (!Array.isArray(raw) || raw.length === 0) {
    return [
      {
        case: "evidence audit",
        evidence: {
          kind: "command",
          ref: "evidence audit",
          quote: "audit returned no matrix",
        },
        verdict: "missing",
        rung: null,
      },
    ];
  }
  return raw.map(normalizeRow);
}

function outcomeFor(state, matrix) {
  if (state === "blocked" || state === "deleted" || state === "landed") {
    return state;
  }
  // Deferred rows are owned elsewhere and never gated here.
  const anyBad = matrix.some(function (r) {
    return r.verdict !== "pass" && r.verdict !== "deferred";
  });
  if (anyBad) return "needs_fix";
  if (state === "approved") return "approved";
  if (state === "todo") return "needs_fix";
  if (state === "handed_off") return "refused";
  return state;
}

export default async function workflow(host) {
  const rawArgs = typeof host.args === "string"
    ? JSON.parse(host.args)
    : (host.args || {});
  const graph = rawArgs.graph;
  const node = rawArgs.node;
  const ts = rawArgs.ts;
  const harness = rawArgs.harness || "muse-code";
  const model = rawArgs.model || "unknown";
  const desk = rawArgs.desk ? String(rawArgs.desk) : "";
  const commit = rawArgs.commit ? String(rawArgs.commit) : "";
  const deskNote = desk ? ("Your working directory is the graph worktree `" + desk + "` - cd there first and run every command from there; do not work in the conductor checkout. ") : "";
  const envPrefix =
    "BP3_HARNESS=" + harness + " BP3_MODEL=" + model + " ";
  const gradeLoad =
    "First load the code-reviewer skill (read_skill " +
    "\"code-reviewer\") and review by its procedure: correctness, " +
    "design patterns, tests, and comments that must agree with " +
    "the code. Its verdict maps ship -> ship, fix_first -> " +
    "needs_fix. ";
  const verifyLoad =
    "First apply the verify stance (read_skill \"verify\" when " +
    "available): judge only on fresh output from the project's " +
    "own check command, never on claimed green. ";
  const refusals = [];
  const runIds = [];
  if (!graph || !node || !ts || !commit) {
    return {
      node: node || null,
      outcome: "refused",
      matrix: [],
      run_ids: runIds,
      refusals: ["missing graph, node, ts, or commit in workflow args"],
    };
  }

  const nodeDir =
    "docs/graphs/" + graph + "/nodes/" + node;

  async function readState() {
    const result = await host.agent({
      label: "read " + node,
      input:
        deskNote +
        "Run exactly `" + envPrefix + "./bin/bp3 g " + graph + " r " + node +
        "` from the graph worktree if one is named above, else the repository root, and return only its stdout JSON " +
        "verdict verbatim as your entire reply, with no prose and no " +
        "code fences. If the command fails, return its stdout JSON " +
        "verdict verbatim instead. Do not edit any file and do not " +
        "call any `bp3 g u` update edge.",
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
    return "BP3_GRAPH=" + graph + " BP3_NODE=" + node + " " + envPrefix;
  }

  const links = {};

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

  function runIdOf(edge, cycle) {
    if (links[edge] && links[edge].run_id) return links[edge].run_id;
    return ts + "-" + edge + "-" + harness + "-" + model +
      "-c" + String(cycle);
  }

  // The link minter (mvp.1): this launcher, before
  // each child spawns. The child never writes its own proof; a
  // refused write means that child never starts.
  async function mintLink(edge, cycle) {
    const fsm = ["handoff", "grade", "verify", "land", "block", "resume"].includes(edge);
    const cmd =
      envPreset(edge, cycle) + "./bin/bp3 harness link mint" +
      (fsm ? " --kind edge --edge " + edge : " --kind node") +
      " --graph " + graph + " --node " + node +
      " --harness " + harness + " --model " + model +
      " --cycle " + String(cycle) +
      (desk ? " --desk " + desk : "");
    const result = await host.agent({
      label: "mint " + node,
      input:
        deskNote +
        "Run exactly `" + cmd + "` from the graph worktree if " +
        "one is named above, else the repository root, and return " +
        "only its stdout JSON verdict verbatim as your entire " +
        "reply, with no prose and no code fences. If the command " +
        "fails, return its stdout JSON verdict verbatim instead. " +
        "Do not edit any file and do not call any `bp3 g u` " +
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
      "`BP3_GRAPH`, `BP3_NODE`, `BP3_HARNESS`, and `BP3_MODEL` " +
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
    return { node: node, outcome: "refused", matrix: [], run_ids: runIds, refusals: refusals };
  }
  if (before.state !== "handed_off" && before.state !== "approved") {
    return { node: node, outcome: before.state, matrix: [], run_ids: runIds, refusals: refusals };
  }
  const bound = before.commit ? String(before.commit) : "";
  if (bound && bound !== commit) {
    refusals.push(
      "E_COMMIT_MISMATCH commit " + commit + " does not bind bound commit " + bound
    );
    return { node: node, outcome: "refused", matrix: [], run_ids: runIds, refusals: refusals };
  }

  // Grade validations pipeline (followup.1): deterministic
  // code mints every adherence row before the audit child
  // spawns. The probe child only transports raw command
  // output verbatim; the plugs above judge it. A pipeline
  // that returns no observations is grader paperwork, so it
  // fails as an audit failure with no FSM verdict.
  const validationsResult = await host.agent({
    label: "validations " + node,
    input:
      deskNote + "You are the grade validations transport for node `" + node +
      "` of graph `" + graph + "`, bound to commit `" + commit + "`. " +
      "Your contract: shell moves the bytes, you move a pointer. First " +
      "run this one command from the graph worktree so the full verbatim " +
      "outputs land in the validations log without passing through your " +
      "reply: `mkdir -p \"$(git rev-parse --git-common-dir)/bp3\" && " +
      "LOG=\"$(git rev-parse --git-common-dir)/bp3/" + ts + "-" + node +
      "-validations.log\" && { echo '=== git_clean ==='; " +
      "git status --porcelain; echo '=== git_show ==='; " +
      "git show --stat " + commit + "; echo '=== handoff_line ==='; " +
      "git show bp3/exp/" + graph + "/" + node + ":" + nodeDir +
      "/ledger.jsonl | tail -1; } > \"$LOG\" 2>&1; echo \"$LOG\"`. " +
      "Then return only a JSON object {log_path, git_clean: {stdout, " +
      "exit}, git_show: {stdout, exit}, run_folders, handoff_line} " +
      "built from these bounded commands, where log_path is the path " +
      "the first command printed (never summarize, never edit any " +
      "file, and do not call any `bp3 g u` update edge): " +
      "(1) `git status --porcelain | head -20` for git_clean; " +
      "(2) `git show --stat " + commit + " | head -3` for git_show; " +
      "(3) for run_folders, run exactly this one shell one-liner " +
      "verbatim from the graph worktree and return its stdout lines " +
      "unchanged as the run_folders array (one line per folder, " +
      "`<folder> tape=yes|no notes=yes|no`; never reformat its lines " +
      "into prose): `for d in " + nodeDir + "/runs/*/; do " +
      "[ -d \"$d\" ] || continue; n=$(basename \"$d\"); " +
      "if [ -f \"$d/tape.log\" ]; then t=yes; else t=no; fi; " +
      "if [ -f \"$d/notes.md\" ]; then u=yes; else u=no; fi; " +
      "echo \"$n tape=$t notes=$u\"; done`; (4) for " +
      "handoff_line, the verbatim last handoff line of `" + nodeDir +
      "/ledger.jsonl` on the node branch (`git show bp3/exp/" + graph +
      "/" + node + ":" + nodeDir + "/ledger.jsonl`), or an empty string " +
      "when there is none. Quote an empty stdout as an empty string; " +
      "the validations pipeline mints its token in code.",
  });
  const validationsVerdict = parseVerdict(validationsResult);
  if (
    !validationsVerdict ||
    typeof validationsVerdict.git_clean !== "object" ||
    typeof validationsVerdict.git_show !== "object"
  ) {
    refusals.push(
      "audit failure: grade validations pipeline returned no observations: " +
      errorText(validationsResult)
    );
    return { node: node, outcome: "audit_failure", matrix: [], run_ids: runIds, refusals: refusals };
  }
  const adherence = runValidations({
    nodeDir: nodeDir,
    commit: commit,
    obs: validationsVerdict,
  });

  if (!(await mintLink("audit", before.cycle))) {
    return { node: node, outcome: "refused", matrix: [], run_ids: runIds, refusals: refusals };
  }

  // Audit: typed evidence matrix, read-only, no state edges.
  const audit = await host.agent({
    label: "audit " + node,
    input:
      deskNote + "You are the audit child for node `" + node + "` of graph `" +
      graph + "`, bound to commit `" + commit + "`. " +
      tapePreamble("audit", before.cycle) +
      " Read the node's EXPERIMENT.md first. Build the evidence " +
      "matrix: one row per Acceptance case (acceptance rows only). " +
      "Adherence rows are minted by the grade validations pipeline " +
      "before you spawn (adherence: no hand-edited state, " +
      "adherence: clean commit, adherence: run folder present, " +
      "adherence: handoff by child, adherence: env run-id stamped); " +
      "never emit an adherence row. Full validation outputs are " +
      "in the validations log `" +
      (validationsVerdict.log_path || "the log_path the transport returned") +
      "` (machine-local, under the git common dir); read it when a " +
      "row needs more than the bounded heads. " + LADDER_TEXT +
      "Every row " +
      "is {case, rung: 1|2|3|4|5a|5b, evidence: {kind: file|command|ledger|grep, ref, " +
      "quote}, verdict: pass|fail|missing|deferred}: name the rung " +
      "that decided the row; a rung 5a row cites its pointer as " +
      "{kind: command, ref: the find-tape --entry call, quote: " +
      "the resolved entry verbatim}; a rung 5b row names its " +
      "escalation (blocked, confused, or lying) in its case or " +
      "quote, and an unnamed whole-tape read is downgraded to " +
      "missing. Quote observed " +
      "evidence verbatim; a gated case with no artifact is verdict " +
      "missing, never pass, and free-string evidence is not a row. " +
      "Deferred is a disposition, not a failure: when an " +
      "Acceptance case's own text in EXPERIMENT.md says it is NOT " +
      "gated by this node and defers it to a named owning node (for " +
      "example `deferred to Node 3`), emit verdict deferred for " +
      "that row with the deferral text itself as typed evidence " +
      "({kind: file, ref: the EXPERIMENT.md line, quote: the " +
      "deferral line verbatim}); never mark such a case missing " +
      "or pass for lacking this node's artifact. A deferral that " +
      "names no owning node is not deferred: emit missing. When a " +
      "command's stdout is empty and its exit is 0, quote " +
      "`(empty stdout, exit 0)` verbatim; never quote an empty " +
      "string as evidence. Corroborate from the per-Run derivation " +
      "log at `<git-common-dir>/bp3/run-lifecycle-derivations/" +
      "<run-id>.jsonl` (resolve the common dir with " +
      "`git rev-parse --git-common-dir`) when it exists. The hooks " +
      "registry witness does not gate this row; outside a named " +
      "rung 5b escalation, never read the whole tape or " +
      "parse tape.log into facts. Judge only; do " +
      "not edit any file and do not call any `bp3 g u` update edge. " +
      "Write the matrix verbatim as JSON in your run folder's " +
      "notes.md, with your brief authored lessons. Reply with only " +
      "a JSON object {ok, run_id, matrix} where matrix is the row " +
      "list you wrote in notes.md.",
  });
  const auditVerdict = parseVerdict(audit);
  if (auditVerdict && typeof auditVerdict.run_id === "string" && auditVerdict.run_id) {
    runIds.push(auditVerdict.run_id);
  }
  let acceptance = auditVerdict && Array.isArray(auditVerdict.matrix)
    ? auditVerdict.matrix
    : null;
  if (acceptance === null || acceptance.length === 0) {
    // No matrix at all is a collection failure, not a defect.
    refusals.push(
      "audit failure: row \"evidence audit\" carries no typed evidence " +
      "(collection error: " +
      (acceptance === null ? errorText(audit) : "audit returned no matrix") +
      "); no verdict was cast and the node cycle is unchanged"
    );
    return { node: node, outcome: "audit_failure", matrix: adherence, run_ids: runIds, refusals: refusals };
  }
  // Audit-internal re-collect (followup.1): one retry naming
  // the untyped rows, inside the same audit Run (no new mint,
  // no FSM verdict, no cycle burn). Rows still untyped after
  // the retry are an explicit audit failure, never needs_fix.
  let missingTyped = untypedRows(acceptance);
  if (missingTyped.length > 0) {
    const recollect = await host.agent({
      label: "audit " + node,
      input:
        deskNote + "Re-collect typed evidence for node `" + node + "` of graph `" +
        graph + "`, bound to commit `" + commit + "`. " +
        tapePreamble("audit", before.cycle) +
        " Your previous audit matrix carried no typed evidence for " +
        "these named rows: " + missingTyped.join(", ") + ". Collect " +
        "observed evidence for exactly those rows and reply with only " +
        "a JSON object {ok, run_id, matrix} whose matrix holds one " +
        "replacement row per named case, each {case, rung: " +
        "1|2|3|4|5a|5b, evidence: {kind: file|command|ledger|grep, " +
        "ref, quote}, verdict: pass|fail|missing|deferred} quoting " +
        "observed evidence verbatim. When a command's stdout is " +
        "empty and its exit is 0, quote `(empty stdout, exit 0)` " +
        "verbatim; never quote an empty string. Judge only; do not " +
        "edit any file and do not call any `bp3 g u` update edge.",
    });
    const recollectVerdict = parseVerdict(recollect);
    if (recollectVerdict && typeof recollectVerdict.run_id === "string" && recollectVerdict.run_id) {
      runIds.push(recollectVerdict.run_id);
    }
    if (recollectVerdict && Array.isArray(recollectVerdict.matrix)) {
      const byCase = {};
      recollectVerdict.matrix.forEach(function (row, i) {
        byCase[rowCase(row, i)] = row;
      });
      acceptance = acceptance.map(function (row, i) {
        const name = rowCase(row, i);
        return Object.prototype.hasOwnProperty.call(byCase, name) ? byCase[name] : row;
      });
    }
    missingTyped = untypedRows(acceptance);
    if (missingTyped.length > 0) {
      const collectionError = recollectVerdict && Array.isArray(recollectVerdict.matrix)
        ? "re-collected row still carried no typed evidence"
        : errorText(recollect);
      for (const name of missingTyped) {
        refusals.push(
          "audit failure: row \"" + name + "\" carries no typed evidence " +
          "after re-collect (collection error: " + collectionError +
          "); no verdict was cast and the node cycle is unchanged"
        );
      }
      return {
        node: node,
        outcome: "audit_failure",
        matrix: adherence.concat(normalizeMatrix(acceptance)),
        run_ids: runIds,
        refusals: refusals,
      };
    }
  }
  const matrix = adherence.concat(normalizeMatrix(acceptance));
  const matrixJson = JSON.stringify(matrix);

  // Grade || verify on the exact bound commit. A gated missing
  // or fail row means the positive verdict is not available to
  // them; deferred rows never gate.
  const gate =
    "The evidence matrix for this grade is: " + matrixJson + ". " +
    "Rows with verdict deferred are not gated by this node (each " +
    "names the node that owns it) and never block: ignore them. " +
    "Any gated row with verdict fail or missing means the work " +
    "is not correct: cast the negative verdict. " + LADDER_TEXT +
    "A rung 5a fail row blocks citing its pointer: cast the " +
    "negative verdict. A rung 5b row is evidence only when it " +
    "names its escalation (blocked, confused, or lying); an " +
    "unnamed whole-tape read, or a clean grade whose matrix " +
    "shows a whole-log read it did not need, is not correct: " +
    "cast the negative verdict. ";
  if (!(await mintLink("grade", before.cycle)) ||
      !(await mintLink("verify", before.cycle))) {
    return { node: node, outcome: "refused", matrix: matrix, run_ids: runIds, refusals: refusals };
  }
  const gradePrompt = deskNote +
    "You are the grade child for node `" + node + "` of graph `" +
    graph + "`, currently in state `" + before.state + "` at cycle " +
    String(before.cycle) + ", bound to commit `" + commit + "`. " +
    gradeLoad + tapePreamble("grade", before.cycle) + gate +
    " Review the work at the bound commit against the node's " +
    "own Acceptance cases in its EXPERIMENT.md (read it first): " +
    "every gated case needs observed evidence (a case deferred " +
    "to a named successor node is not gated here), and any open " +
    "design question in the node means it was not done properly. Judge " +
    "only; do not edit the work. Then call the state " +
    "edge directly yourself, binding the exact commit: " +
    "`" + envPreset("grade", before.cycle) + "./bin/bp3 g " + graph + " u " + node +
    " grade --verdict ship --commit " + commit +
    " --reason \"<short reason>\"` when the work is correct, " +
    "or the same call with `--verdict needs_fix` when it is " +
    "not. Children call `bp3 g u` directly; never only return " +
    "a verdict for the parent to relay. Reply with only a " +
    "JSON object {ok, run_id, commit, verdict} where verdict " +
    "is the JSON printed by the grade call.";
  const verifyPrompt = deskNote +
    "You are the verify child for node `" + node + "` of graph `" +
    graph + "`, currently in state `" + before.state + "` at cycle " +
    String(before.cycle) + ", bound to commit `" + commit + "`. " +
    verifyLoad + tapePreamble("verify", before.cycle) + gate +
    " Run the node's checks against the bound commit and judge " +
    "only; do not edit the work. Then call the state edge " +
    "directly yourself, binding the exact commit: " +
    "`" + envPreset("verify", before.cycle) + "./bin/bp3 g " + graph + " u " + node +
    " verify --verdict pass --commit " + commit +
    " --reason \"<short reason>\"` when every check passes, " +
    "or the same call with `--verdict fail` when any check " +
    "fails. Children call `bp3 g u` directly; never only " +
    "return a verdict for the parent to relay. Reply with " +
    "only a JSON object {ok, run_id, commit, verdict} where " +
    "verdict is the JSON printed by the verify call.";
  const stageResults = await host.parallel([
    { label: "grade " + node, input: gradePrompt },
    { label: "verify " + node, input: verifyPrompt },
  ]);
  for (let i = 0; i < stageResults.length; i++) {
    const v = parseVerdict(stageResults[i]);
    if (v && typeof v.run_id === "string" && v.run_id) {
      runIds.push(v.run_id);
    }
  }

  const after = await readState();
  if (after.state === "unknown") {
    refusals.push("re-read after grade failed: " + (after.raw || "no verdict"));
    for (let i = 0; i < stageResults.length; i++) {
      refusals.push(errorText(stageResults[i]));
    }
    return { node: node, outcome: "refused", matrix: matrix, run_ids: runIds, refusals: refusals };
  }
  const outcome = outcomeFor(after.state, matrix);
  // Verdict race (followup.1): grade and verify cast in
  // parallel; the first cast can move state so the second
  // cast's edge is no longer legal. When the re-read shows
  // state moved, that E_ILLEGAL_EDGE is an expected verdict
  // race and is named as such, never an unexplained refusal.
  const stageEdges = ["grade", "verify"];
  let raced = false;
  for (let i = 0; i < stageResults.length; i++) {
    if (textOf(stageResults[i]).indexOf("E_ILLEGAL_EDGE") >= 0 && after.state !== "handed_off") {
      raced = true;
      refusals.push(
        "expected verdict race: " + stageEdges[i] + " cast refused with " +
        "E_ILLEGAL_EDGE after the parallel verdict moved state to " +
        after.state + "; the refused cast is expected and does not " +
        "change the outcome"
      );
    }
  }
  if (outcome === "refused" && !raced) {
    for (let i = 0; i < stageResults.length; i++) {
      refusals.push(errorText(stageResults[i]));
    }
  }
  return { node: node, outcome: outcome, matrix: matrix, run_ids: runIds, refusals: refusals };
}
