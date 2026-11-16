// induct-grade: judge one submitted exp on its bound commit.
// Installed to .agents/workflows/induct-grade.js by
// `bp3 skills install`. The grade climbs the evidence ladder
// (mvp.7): records, diff, tests run, style, then tape via
// derivation pointers (find-tape --entry); the whole tape is
// escalation only, blocked/confused/lying and named. Audit
// child builds the typed evidence matrix (acceptance rows +
// adherence rows, no edges), then
// review and check children run in parallel on the exact bound
// commit and call their verdict edges directly. Grade children
// never edit the work. As the named InitRecord writer (mvp.8)
// this launcher records each child's InitRecord via
// `bp3 harness record-init` before that child spawns; no child
// writes its own proof. Returns {outcome, matrix, run_ids,
// refusals}; replay on the same commit is safe: the audit is
// read-only and re-cast verdicts bind the same commit.
// Args are supplied by the calling induct skill as
// {quest, exp, ts, harness, model, commit}; ts is a UTC compact
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

// Deferred is a disposition, not a failure: the exp's own
// text defers the case to a named owning exp and the row's
// evidence is that deferral text. A deferral naming no owner
// is no deferral at all.
function deferralNamesOwner(text) {
  return /defer/i.test(text) && /\bexp[\s-]*\d+\b/i.test(text);
}

// The evidence ladder (QUEST.md contract, mvp.7), in order;
// each rung only when the ones above leave the verdict
// undecided. Rung 5 splits: 5a resolves derivation pointers
// one entry at a time, 5b reads the whole tape and is
// escalation only.
const LADDER_RUNGS = ["1", "2", "3", "4", "5a", "5b"];
const LADDER_TEXT =
  "Climb the evidence ladder in order, each rung only when " +
  "the ones above leave the verdict undecided: rung 1 the " +
  "quest and exp records (what was asked); rung 2 committed " +
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
  if (state === "submitted") return "refused";
  return state;
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
  const commit = rawArgs.commit ? String(rawArgs.commit) : "";
  const deskNote = desk ? ("Your working directory is the quest worktree `" + desk + "` - cd there first and run every command from there; do not work in the conductor checkout. ") : "";
  const envPrefix =
    "BP3_HARNESS=" + harness + " BP3_MODEL=" + model + " ";
  const reviewLoad =
    "First load the code-reviewer skill (read_skill " +
    "\"code-reviewer\") and review by its procedure: correctness, " +
    "design patterns, tests, and comments that must agree with " +
    "the code. Its verdict maps ship -> ship, fix_first -> " +
    "needs_fix. ";
  const checkLoad =
    "First apply the verify stance (read_skill \"verify\" when " +
    "available): judge only on fresh output from the project's " +
    "own check command, never on claimed green. ";
  const refusals = [];
  const runIds = [];
  if (!quest || !exp || !ts || !commit) {
    return {
      exp: exp || null,
      outcome: "refused",
      matrix: [],
      run_ids: runIds,
      refusals: ["missing quest, exp, ts, or commit in workflow args"],
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
  // each child spawns. The child never writes its own proof; a
  // refused write means that child never starts.
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
    return { exp: exp, outcome: "refused", matrix: [], run_ids: runIds, refusals: refusals };
  }
  if (before.state !== "submitted" && before.state !== "approved") {
    return { exp: exp, outcome: before.state, matrix: [], run_ids: runIds, refusals: refusals };
  }
  const bound = before.commit ? String(before.commit) : "";
  if (bound && bound !== commit) {
    refusals.push(
      "E_COMMIT_MISMATCH commit " + commit + " does not bind bound commit " + bound
    );
    return { exp: exp, outcome: "refused", matrix: [], run_ids: runIds, refusals: refusals };
  }

  if (!(await recordInit("audit", before.cycle))) {
    return { exp: exp, outcome: "refused", matrix: [], run_ids: runIds, refusals: refusals };
  }

  // Audit: typed evidence matrix, read-only, no state edges.
  const audit = await host.agent({
    label: "audit " + exp,
    input:
      deskNote + "You are the audit child for exp `" + exp + "` of quest `" +
      quest + "`, bound to commit `" + commit + "`. " +
      tapePreamble("audit", before.cycle) +
      " Read the exp's EXPERIMENT.md first. Build the evidence " +
      "matrix: one row per Acceptance case (acceptance rows), plus " +
      "adherence rows for the build Run that produced this commit " +
      "(submit edge called by the child directly, env-set run-id " +
      "stamped by bp3, clean commit, tape.log and notes.md " +
      "present in its run folder, no hand-edited state). " + LADDER_TEXT +
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
      "gated by this exp and defers it to a named owning exp (for " +
      "example `deferred to Exp 3`), emit verdict deferred for " +
      "that row with the deferral text itself as typed evidence " +
      "({kind: file, ref: the EXPERIMENT.md line, quote: the " +
      "deferral line verbatim}); never mark such a case missing " +
      "or pass for lacking this exp's artifact. A deferral that " +
      "names no owning exp is not deferred: emit missing. For " +
      "the adherence row `env-set run-id`, quote " +
      "the bp3-stamped ledger line for the submit edge (the mvp.1 " +
      "mechanism: BP3_RUN_ID arrives via environment and bp3 stamps " +
      "it into the verdict and the ledger line): find the submit " +
      "line whose run_id is the build Run that produced this commit " +
      "(the submit run folder under this exp's runs/) and quote it " +
      "as {kind: ledger, ref: the exp ledger submit line, quote: " +
      "the line verbatim}. Corroborate from the per-Run derivation " +
      "log at `<git-common-dir>/bp3/run-lifecycle-derivations/" +
      "<run-id>.jsonl` (resolve the common dir with " +
      "`git rev-parse --git-common-dir`) when it exists. The hooks " +
      "registry witness does not gate this row; outside a named " +
      "rung 5b escalation, never read the whole tape or " +
      "parse tape.log into facts. Judge only; do " +
      "not edit any file and do not call any `bp3 q u` update edge. " +
      "Write the matrix verbatim as JSON in your run folder's " +
      "notes.md, with your brief authored lessons. Reply with only " +
      "a JSON object {ok, run_id, matrix} where matrix is the row " +
      "list you wrote in notes.md.",
  });
  const auditVerdict = parseVerdict(audit);
  if (auditVerdict && typeof auditVerdict.run_id === "string" && auditVerdict.run_id) {
    runIds.push(auditVerdict.run_id);
  }
  if (!auditVerdict || !Array.isArray(auditVerdict.matrix)) {
    refusals.push("audit returned no matrix: " + errorText(audit));
  }
  const matrix = normalizeMatrix(auditVerdict ? auditVerdict.matrix : null);
  const matrixJson = JSON.stringify(matrix);

  // Review || check on the exact bound commit. A gated missing
  // or fail row means the positive verdict is not available to
  // them; deferred rows never gate.
  const gate =
    "The evidence matrix for this grade is: " + matrixJson + ". " +
    "Rows with verdict deferred are not gated by this exp (each " +
    "names the exp that owns it) and never block: ignore them. " +
    "Any gated row with verdict fail or missing means the work " +
    "is not correct: cast the negative verdict. " + LADDER_TEXT +
    "A rung 5a fail row blocks citing its pointer: cast the " +
    "negative verdict. A rung 5b row is evidence only when it " +
    "names its escalation (blocked, confused, or lying); an " +
    "unnamed whole-tape read, or a clean grade whose matrix " +
    "shows a whole-log read it did not need, is not correct: " +
    "cast the negative verdict. ";
  const reviewPrompt = deskNote +
    "You are the review child for exp `" + exp + "` of quest `" +
    quest + "`, currently in state `" + before.state + "` at cycle " +
    String(before.cycle) + ", bound to commit `" + commit + "`. " +
    reviewLoad + tapePreamble("review", before.cycle) + gate +
    " Review the work at the bound commit against the exp's " +
    "own Acceptance cases in its EXPERIMENT.md (read it first): " +
    "every gated case needs observed evidence (a case deferred " +
    "to a named successor exp is not gated here), and any open " +
    "design question in the exp means it was not done properly. Judge " +
    "only; do not edit the work. Then call the state " +
    "edge directly yourself, binding the exact commit: " +
    "`" + envPreset("review", before.cycle) + "./bin/bp3 q " + quest + " u " + exp +
    " review --verdict ship --commit " + commit +
    " --reason \"<short reason>\"` when the work is correct, " +
    "or the same call with `--verdict needs_fix` when it is " +
    "not. Children call `bp3 q u` directly; never only return " +
    "a verdict for the parent to relay. Reply with only a " +
    "JSON object {ok, run_id, commit, verdict} where verdict " +
    "is the JSON printed by the review call.";
  const checkPrompt = deskNote +
    "You are the check child for exp `" + exp + "` of quest `" +
    quest + "`, currently in state `" + before.state + "` at cycle " +
    String(before.cycle) + ", bound to commit `" + commit + "`. " +
    checkLoad + tapePreamble("check", before.cycle) + gate +
    " Run the exp's checks against the bound commit and judge " +
    "only; do not edit the work. Then call the state edge " +
    "directly yourself, binding the exact commit: " +
    "`" + envPreset("check", before.cycle) + "./bin/bp3 q " + quest + " u " + exp +
    " check --verdict pass --commit " + commit +
    " --reason \"<short reason>\"` when every check passes, " +
    "or the same call with `--verdict fail` when any check " +
    "fails. Children call `bp3 q u` directly; never only " +
    "return a verdict for the parent to relay. Reply with " +
    "only a JSON object {ok, run_id, commit, verdict} where " +
    "verdict is the JSON printed by the check call.";
  if (!(await recordInit("review", before.cycle)) ||
      !(await recordInit("check", before.cycle))) {
    return { exp: exp, outcome: "refused", matrix: matrix, run_ids: runIds, refusals: refusals };
  }
  const stageResults = await host.parallel([
    { label: "review " + exp, input: reviewPrompt },
    { label: "check " + exp, input: checkPrompt },
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
    return { exp: exp, outcome: "refused", matrix: matrix, run_ids: runIds, refusals: refusals };
  }
  const outcome = outcomeFor(after.state, matrix);
  if (outcome === "refused") {
    for (let i = 0; i < stageResults.length; i++) {
      refusals.push(errorText(stageResults[i]));
    }
  }
  return { exp: exp, outcome: outcome, matrix: matrix, run_ids: runIds, refusals: refusals };
}
