// Mock-host test for skills/bp3g/workflows/bp3g-grade.js.
// Covers the node Acceptance table: typed matrix returned, a
// missing-evidence row blocks approval, an untyped row never
// carries pass, a deferred row naming its owning node never
// blocks (an unnamed or untyped deferral is missing), the
// audit quotes env-preset evidence from the stamped ledger line,
// row order never changes the outcome, replay on the same
// commit returns the same matrix, the ladder fixtures (lying
// pointer blocks, clean shows zero whole-log reads, confused
// whole-tape escalation must name itself), and grade children are
// judge-only (audit spawns no edge, grade/verify bind the
// exact commit). Followup.1: the validations pipeline mints
// adherence rows in code before the audit spawns (empty stdout
// quoted as the machine token), an untyped acceptance row is
// re-collected inside the audit (named rows, no cycle burn),
// evidence still uncollectable is an explicit audit_failure
// with no verdict cast. Followup.5 (pure-grade): audit, grade,
// and verify children return verdicts as data (zero `bp3 g u`
// calls); the looper applies exactly one combined cast, with
// named pushbacks (superseded, empty fix, blocked), a fix
// ledger OPEN entry, audit reuse of prior typed evidence,
// and a named mechanical fix that never blocks while the
// cycle cap counts disagreement cycles only.
import workflow from "../skills/bp3g/workflows/bp3g-grade.js";

const TS = "20260101T000000Z";
const COMMIT = "abc1234";
let failures = 0;
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); failures++; }
}

function passRow(name) {
  return {
    case: name,
    evidence: { kind: "command", ref: "test/g.sh", quote: "q tests: ok" },
    verdict: "pass",
  };
}

function deferredRow(name) {
  return {
    case: name,
    evidence: {
      kind: "file",
      ref: "docs/graphs/toy/nodes/fx/NODE.md:57",
      quote: "| " + name + " | NOT gated by this node |",
    },
    verdict: "deferred",
  };
}

const GOOD_OBS = {
  git_clean: { stdout: "", exit: 0 },
  git_show: { stdout: COMMIT + " subject\n file | 1 +\n", exit: 0 },
  run_folders: ["20260101T000000Z-handoff-muse-code-test-model-c1 tape=yes notes=yes"],
  handoff_line: '{"edge":"handoff","run_id":"r-build","commit":"' + COMMIT + '"}',
};

function rowNamed(result, name) {
  return result.matrix.find((r) => r.case === name);
}

// reads: state replies in order; audit replies with auditRows
// (or auditSeq per audit call); grade/verify reply as cast
// verdicts. Records stage inputs.
function mockHost({ reads, auditRows, auditSeq, validationsObs, stageReplies, initFails, extraArgs }) {
  let readIdx = 0;
  let auditIdx = 0;
  const inputs = { reads: [] };
  const order = [];
  const inits = [];
  const host = {
    args: Object.assign({ graph: "toy", node: "fx", ts: TS, harness: "muse-code", model: "test-model", commit: COMMIT }, extraArgs || {}),
    async agent({ label, input }) {
      if (label.startsWith("validations")) {
        order.push("validations");
        inputs.validations = input;
        return JSON.stringify(validationsObs || GOOD_OBS);
      }
      if (input.includes("harness link mint")) {
        order.push("init");
        inputs.init = input;
        const e = input.match(/--edge (\S+)/);
        const edge = e ? e[1] : "audit";
        const runId = TS + "-" + edge + "-muse-code-test-model-c1";
        inits.push(runId);
        if (initFails) {
          return JSON.stringify({ ok: false, error: { code: "E_DEPTH" } });
        }
        return JSON.stringify({ ok: true, token: "bp3link_test-" + edge, run_id: runId, harness: "muse-code" });
      }
      if (label.startsWith("apply")) {
        inputs.apply = input;
        order.push("apply");
        return JSON.stringify({ ok: true, state: "approved" });
      }
      if (label.startsWith("read ") || input.startsWith("Run exactly")) {
        inputs.reads.push(input);
        return JSON.stringify(reads[Math.min(readIdx++, reads.length - 1)]);
      }
      const edge = label.split(" ")[0];
      if (edge === "audit" && input.includes("Re-collect typed evidence")) {
        inputs.recollect = input;
        order.push("recollect");
        const seq = auditSeq || [auditRows];
        const matrix = seq[Math.min(auditIdx++, seq.length - 1)];
        return JSON.stringify({ ok: true, run_id: "r-audit", matrix: matrix });
      }
      inputs[edge] = input;
      order.push(edge);
      if (edge === "audit") {
        const seq = auditSeq || [auditRows];
        const matrix = seq[Math.min(auditIdx++, seq.length - 1)];
        return JSON.stringify({ ok: true, run_id: "r-audit", matrix: matrix });
      }
      if (stageReplies && typeof stageReplies[edge] === "string") {
        return stageReplies[edge];
      }
      return JSON.stringify({ ok: true, run_id: "r-" + edge, commit: COMMIT, verdict: { ok: true } });
    },
    async parallel(calls) {
      const out = [];
      for (const c of calls) out.push(await host.agent(c));
      return out;
    },
  };
  return { host, inputs, order, inits };
}

const handedOff = { state: "handed_off", cycle: 1, commit: COMMIT, legal_edges: ["grade", "verify"] };
const approved = { state: "approved", cycle: 1, commit: COMMIT, legal_edges: ["land"] };

// --- grade a handed_off node: outcome + typed matrix, bindings ---
{
  const { host, inputs, order, inits } = mockHost({
    reads: [handedOff, approved],
    auditRows: [passRow("acceptance: a"), passRow("adherence: tape present")],
  });
  const result = await workflow(host);
  assert(result.outcome === "approved", "all-pass grade approves, got " + result.outcome);
  assert(Array.isArray(result.matrix) && result.matrix.length === 7, "matrix has 5 adherence + 2 acceptance rows, got " + result.matrix.length);
  assert(result.matrix.every((r) => r.verdict === "pass"), "all rows pass");
  assert(order.join(",") === "validations,init,audit,init,init,grade,verify,apply", "validations precede the audit, writer precedes each pure child, looper applies last, got " + order.join(","));
  assert(result.casts === 1, "exactly one verdict cast per grade, got " + result.casts);
  assert(result.verdict && result.verdict.outcome === "ship", "pure verdict is ship data");
  assert(Array.isArray(result.ledger) && result.ledger.length === 0, "ship opens no fix ledger entry");
  assert(inits.join(",") === [TS + "-audit-muse-code-test-model-c1", TS + "-grade-muse-code-test-model-c1", TS + "-verify-muse-code-test-model-c1"].join(","),
    "mints name every grade run-id, got " + inits.join(","));
  for (const edge of ["audit", "grade", "verify"]) {
    const input = inputs[edge];
    assert(input, edge + " child was spawned");
    assert(input.includes("runs/" + TS + "-" + edge + "-muse-code-test-model-c1"),
      edge + " run folder matches the minted run-id");
    assert(!input.includes("Prefix your FIRST"),
      edge + " brief carries no first-command prefix instruction");
    assert(input.includes("arrives via the"),
      edge + " is told the run-id arrives via the claim");
  }
  for (const edge of ["grade", "verify"]) {
    assert(inputs[edge].includes("link claim bp3link_test-" + edge), edge + " brief carries its claim token");
    assert(inputs[edge].includes("BP3_RUN_ID=<that run_id>"), edge + " is told to stamp the claimed run-id");
  }
  assert(inputs.audit.includes("do not call any `bp3 g u` update edge"),
    "audit child spawns no state edge");
  assert(inputs.audit.includes("notes.md"), "audit writes matrix in its notes.md");
  assert(inputs.audit.includes("acceptance rows only"), "audit builds acceptance rows only");
  assert(!inputs.audit.includes("adherence rows for the build Run"),
    "audit brief no longer asks the LLM for adherence rows");
  assert(inputs.validations.includes("git status --porcelain"),
    "validations transport runs git status --porcelain");
  assert(inputs.validations.includes("shell moves the bytes, you move a pointer"),
    "validations transport is pointer-contracted (log file, not verbatim JSON)");
  assert(inputs.validations.includes("-validations.log"),
    "validations transport writes the .git/bp3 validations log");
  assert(inputs.validations.includes("git show --stat " + COMMIT + " | head -3"),
    "validations transport bounds git_show to its head for the JSON return");
  assert(inputs.validations.includes("git show bp3/node/toy/fx:docs/graphs/toy/nodes/fx/ledger.jsonl"),
    "validations probe resolves the handoff ledger via the post-migration node branch");
  assert(!inputs.validations.includes("bp3/exp/"),
    "validations probe carries no retired bp3/exp hardcode");
  for (const name of ["adherence: no hand-edited state", "adherence: clean commit", "adherence: run folder present", "adherence: handoff by child", "adherence: env run-id stamped"]) {
    assert(rowNamed(result, name) && rowNamed(result, name).verdict === "pass",
      "validations minted " + name);
  }
  for (const edge of ["grade", "verify"]) {
    assert(inputs[edge].includes("do not call any `bp3 g u` update edge"),
      edge + " child is pure (zero bp3 g u calls)");
    assert(inputs[edge].includes("return your verdict as data") ||
           inputs[edge].includes("Return your verdict as data"),
      edge + " child returns its verdict as data");
    assert(!inputs[edge].includes("u fx " + edge + " --verdict"),
      edge + " brief carries no cast command");
    assert(inputs[edge].includes(COMMIT), edge + " judges the exact bound commit");
  }
  assert(inputs.apply.includes("grade --verdict ship --commit " + COMMIT + " --verify-verdict pass"),
    "looper's one cast binds the exact commit with the combined verdict");
  assert((inputs.apply.match(/bp3 g /g) || []).length === 1,
    "looper apply runs exactly one bp3 command");
  assert(result.run_ids.join(",") === [TS + "-audit-muse-code-test-model-c1", "r-audit", TS + "-grade-muse-code-test-model-c1", TS + "-verify-muse-code-test-model-c1", "r-grade", "r-verify"].join(","),
    "run_ids collect mints and every grade child, got " + result.run_ids.join(","));
}

// --- no artifact: row missing, outcome cannot be approved ---
{
  const missing = passRow("acceptance: b");
  missing.verdict = "missing";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), missing] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: b").verdict === "missing", "missing row stays missing");
  assert(result.outcome === "needs_fix", "missing row blocks approval, got " + result.outcome);
}

// --- untyped evidence never reaches the FSM; still untyped
// --- after one re-collect it is an explicit audit failure ---
{
  const untyped = { case: "acceptance: c", evidence: "looked fine", verdict: "pass" };
  const { host, order } = mockHost({ reads: [handedOff, approved], auditRows: [untyped] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: c").verdict === "missing", "untyped pass downgraded to missing");
  assert(result.outcome === "audit_failure", "untyped row is an audit failure, got " + result.outcome);
  assert(result.outcome !== "needs_fix", "audit failure is distinguishable from needs_fix");
  assert(order.includes("recollect"), "audit re-collected the named row, got " + order.join(","));
  assert(!order.includes("grade") && !order.includes("verify"), "no verdict cast on untyped evidence");
  assert(result.refusals.some((r) => r.includes("audit failure") && r.includes("acceptance: c") && r.includes("collection error")),
    "audit failure names the row and the collection error");
}

// --- row order never changes the outcome ---
{
  const fail = passRow("acceptance: d");
  fail.verdict = "fail";
  const a = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), fail] });
  const b = mockHost({ reads: [handedOff, approved], auditRows: [fail, passRow("acceptance: a")] });
  const ra = await workflow(a.host);
  const rb = await workflow(b.host);
  assert(ra.outcome === rb.outcome && ra.outcome === "needs_fix",
    "row order keeps outcome, got " + ra.outcome + "/" + rb.outcome);
}

// --- replay on the same commit: same matrix, still approved ---
{
  const rows = [passRow("acceptance: a")];
  const first = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const r1 = await workflow(first.host);
  const replay = mockHost({ reads: [approved, approved], auditRows: rows });
  const r2 = await workflow(replay.host);
  assert(r2.outcome === "approved", "replay on approved commit approves, got " + r2.outcome);
  assert(JSON.stringify(r2.matrix) === JSON.stringify(r1.matrix), "replay returns the same matrix");
}

// --- not handed_off: no grade children spawn ---
{
  const todo = { state: "todo", cycle: 1, commit: null, legal_edges: ["handoff"] };
  const { host, order } = mockHost({ reads: [todo], auditRows: [passRow("acceptance: a")] });
  const result = await workflow(host);
  assert(result.outcome === "todo", "todo node is not graded, got " + result.outcome);
  assert(order.length === 0, "no grade children spawn for todo");
}

// --- commit mismatch and missing args refuse without children ---
{
  const other = { state: "handed_off", cycle: 1, commit: "def5678", legal_edges: ["grade", "verify"] };
  const { host, order } = mockHost({ reads: [other], auditRows: [passRow("acceptance: a")] });
  const result = await workflow(host);
  assert(result.outcome === "refused", "commit mismatch refuses, got " + result.outcome);
  assert(order.length === 0, "no grade children spawn on mismatch");

  const noCommit = {
    args: { graph: "toy", node: "fx", ts: TS },
    async agent() { throw new Error("must not spawn"); },
    async parallel() { throw new Error("must not spawn"); },
  };
  const refused = await workflow(noCommit);
  assert(refused.outcome === "refused", "missing commit refuses");
}

// --- deferred row: owned elsewhere, excluded from the gate ---
{
  const { host, inputs } = mockHost({
    reads: [handedOff, approved],
    auditRows: [
      passRow("acceptance: a"),
      deferredRow("acceptance: full cycle — NOT gated by this node, deferred to Node 3"),
    ],
  });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: full cycle — NOT gated by this node, deferred to Node 3").verdict === "deferred", "deferred row stays deferred");
  assert(rowNamed(result, "acceptance: full cycle — NOT gated by this node, deferred to Node 3").evidence.kind === "file", "deferred row keeps its typed deferral evidence");
  assert(result.outcome === "approved", "deferred row does not block approval, got " + result.outcome);
  assert(inputs.audit.includes("verdict: pass|fail|missing|deferred"),
    "audit may emit deferred rows");
  assert(!inputs.audit.includes("bp3-run-registry"),
    "audit never names the retired run registry");
  assert(inputs.audit.includes("run-lifecycle-derivations"),
    "audit corroborates from the per-Run derivation log");
  assert(inputs.audit.includes("stamped"), "audit quotes the stamped ledger line");
  assert(inputs.grade.includes("deferred"), "grade is told deferred rows never block");
  assert(inputs.verify.includes("deferred"), "verify is told deferred rows never block");
}

// --- deferral naming no owning node is missing, not deferred ---
{
  const unnamed = deferredRow("acceptance: later work — deferred");
  unnamed.evidence.quote = "deferred to a later node";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), unnamed] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: later work — deferred").verdict === "missing", "unnamed deferral downgraded to missing");
  assert(result.outcome === "needs_fix", "unnamed deferral blocks approval, got " + result.outcome);
}

// --- deferral text naming its owner is deferred even if mislabeled missing ---
{
  const mislabeled = deferredRow("acceptance: full cycle — NOT gated by this node, deferred to Node 3");
  mislabeled.verdict = "missing";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), mislabeled] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: full cycle — NOT gated by this node, deferred to Node 3").verdict === "deferred", "mislabeled deferral upgraded to deferred");
  assert(result.outcome === "approved", "mislabeled deferral does not block approval, got " + result.outcome);
}

// --- deferred without typed evidence is missing, never deferred ---
{
  const untyped = { case: "acceptance: x — deferred to Node 3", evidence: "deferred to Node 3", verdict: "deferred" };
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [untyped] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: x — deferred to Node 3").verdict === "missing", "untyped deferred downgraded to missing");
  assert(result.outcome === "audit_failure", "untyped deferred is an audit failure, got " + result.outcome);
}

// --- verdict outside pass|fail|missing|deferred is coerced ---
{
  const bogus = passRow("acceptance: e");
  bogus.verdict = "bogus";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [bogus] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: e").verdict === "missing", "unknown verdict coerced to missing");
  assert(result.outcome === "needs_fix", "coerced row blocks approval, got " + result.outcome);
}

// --- generated matrices: order never matters, deferred never gates ---
{
  const kinds = ["pass", "fail", "missing", "deferred"];
  function rowFor(v, i) {
    if (v === "deferred") return deferredRow("acceptance: d" + i + " — deferred to Node 3");
    const r = passRow("acceptance: r" + i);
    r.verdict = v;
    return r;
  }
  async function outcomeOf(rows) {
    const { host } = mockHost({ reads: [handedOff, approved], auditRows: rows });
    return (await workflow(host)).outcome;
  }
  const seqs = [[]];
  for (let len = 1; len <= 3; len++) {
    const prev = seqs.filter((s) => s.length === len - 1);
    for (const p of prev) for (const k of kinds) seqs.push(p.concat(k));
  }
  for (const seq of seqs) {
    const got = await outcomeOf(seq.map(rowFor));
    const gatedBad = seq.some((v) => v !== "pass" && v !== "deferred");
    const want = seq.length === 0 ? "audit_failure" : gatedBad ? "needs_fix" : "approved";
    assert(got === want, "outcome for [" + seq.join(",") + "] is " + want + ", got " + got);
    const rev = await outcomeOf(seq.slice().reverse().map(rowFor));
    assert(rev === got, "row order keeps outcome for [" + seq.join(",") + "]");
  }
}

// --- evidence ladder (mvp.7): prompts climb rungs in order ---
{
  const { host, inputs } = mockHost({
    reads: [handedOff, approved],
    auditRows: [passRow("acceptance: a")],
  });
  await workflow(host);
  assert(inputs.audit.includes("rung 1 the graph and node records"), "audit starts at rung 1 (records)");
  assert(inputs.audit.includes("rung 2 committed code and git diff"), "audit climbs to rung 2 (diff)");
  assert(inputs.audit.includes("rung 3 demos and tests, run"), "audit climbs to rung 3 (tests run)");
  assert(inputs.audit.includes("rung 4 style"), "audit climbs to rung 4 (style)");
  assert(inputs.audit.includes("bp3 harness find-tape --run-id <run-id> --entry"), "audit resolves pointers via find-tape --entry");
  assert(inputs.audit.includes("rung 5b the whole tape, escalation only when blocked, confused, or lying"), "whole tape is named escalation only");
  assert(inputs.audit.includes("zero whole-log reads"), "clean grade shows zero whole-log reads");
  assert(inputs.audit.includes("rung: 1|2|3|4|5a|5b"), "rows name the rung that decided them");
  assert(inputs.grade.includes("find-tape --run-id"), "grade is told the ladder");
  assert(inputs.verify.includes("find-tape --run-id"), "verify is told the ladder");
  assert(inputs.grade.includes("unnamed whole-tape read"), "grade gates unnamed whole-tape reads");
  assert(inputs.verify.includes("unnamed whole-tape read"), "verify gates unnamed whole-tape reads");
}

function rungRow(name, rung, verdict, quote) {
  return {
    case: name,
    rung: rung,
    evidence: {
      kind: "command",
      ref: "bp3 harness find-tape --run-id R --entry E",
      quote: quote || "entry E observed verbatim",
    },
    verdict: verdict,
  };
}

// --- lying fixture: rungs 1-4 clean, rung 5a pointer contradicts ---
{
  const rows = [
    rungRow("acceptance: records", "1", "pass"),
    rungRow("acceptance: diff clean", "2", "pass"),
    rungRow("acceptance: tests pass", "3", "pass"),
    rungRow("acceptance: style", "4", "pass"),
    rungRow("acceptance: claim holds", "5a", "fail", "entry E contradicts the claim"),
  ];
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const result = await workflow(host);
  assert(result.outcome === "needs_fix", "lying fixture blocks, got " + result.outcome);
  assert(rowNamed(result, "acceptance: claim holds").verdict === "fail", "pointer row stays fail");
  assert(rowNamed(result, "acceptance: claim holds").rung === "5a", "pointer row keeps rung 5a");
  assert(rowNamed(result, "acceptance: claim holds").evidence.ref.includes("find-tape --run-id"), "block cites the rung-5 pointer");
}

// --- clean fixture: decided at rungs 1-4, zero whole-log reads ---
{
  const rows = [
    rungRow("acceptance: records", "1", "pass"),
    rungRow("acceptance: diff clean", "2", "pass"),
    rungRow("acceptance: tests pass", "3", "pass"),
    rungRow("acceptance: style", "4", "pass"),
  ];
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const result = await workflow(host);
  assert(result.outcome === "approved", "clean fixture approves, got " + result.outcome);
  assert(result.matrix.every((r) => r.rung !== "5b"), "clean trace shows zero whole-log reads");
}

// --- confused fixture: named whole-tape escalation is allowed ---
{
  const rows = [
    rungRow("acceptance: records", "1", "pass"),
    rungRow("acceptance: whole tape decides", "5b", "pass", "confused grade: rungs 1-5a undecided, whole tape read"),
  ];
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: whole tape decides").verdict === "pass", "named escalation keeps its verdict");
  assert(rowNamed(result, "acceptance: whole tape decides").rung === "5b", "escalation row keeps rung 5b");
  assert(result.outcome === "approved", "named confused escalation can decide, got " + result.outcome);
}

// --- unnamed whole-tape read never carries a grade ---
{
  const rows = [
    rungRow("acceptance: records", "1", "pass"),
    rungRow("acceptance: tape looked fine", "5b", "pass", "read the whole tape"),
  ];
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: tape looked fine").verdict === "missing", "unnamed whole-tape pass downgraded to missing");
  assert(result.outcome === "needs_fix", "unnamed whole-tape read blocks approval, got " + result.outcome);
}

// --- a rung outside the ladder is no rung ---
{
  const bogus = rungRow("acceptance: records", "9", "pass");
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [bogus] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: records").rung === null, "unknown rung coerced to null");
  assert(rowNamed(result, "acceptance: records").verdict === "pass", "row still judged on its typed evidence");
}

// --- writer refused: no grade child starts (mvp.8) ---
{
  const { host, order } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a")], initFails: true });
  const result = await workflow(host);
  assert(result.outcome === "refused", "writer refusal refuses the grade, got " + result.outcome);
  assert(order.join(",") === "validations,init", "no grade child spawns after a refused mint, got " + order.join(","));
  assert(result.refusals.some((r) => r.includes("link mint")), "refusal names link mint");
}

// --- config.1 replay: lazy audit, green product, re-collect
// --- approves with no extra mint and no cycle burn ---
{
  const lazy = { case: "acceptance: a", evidence: "looked fine", verdict: "pass" };
  const { host, inputs, order, inits } = mockHost({
    reads: [handedOff, approved],
    auditSeq: [[lazy], [passRow("acceptance: a")]],
  });
  const result = await workflow(host);
  assert(result.outcome === "approved", "re-collected grade approves, got " + result.outcome);
  assert(inputs.recollect && inputs.recollect.includes("acceptance: a"), "re-collect names the untyped row");
  assert(inits.length === 3, "audit retry mints no new link, got " + inits.join(","));
  assert(order.join(",") === "validations,init,audit,recollect,init,init,grade,verify,apply",
    "one audit-internal retry, then pure verdicts and one cast, got " + order.join(","));
  assert(result.matrix.every((r) => r.evidence && typeof r.evidence.quote === "string" && r.evidence.quote !== ""),
    "every judged row carries typed evidence");
}

// --- property: no verdict is emitted while a row lacks
// --- typed evidence, over evidence shapes ---
{
  const shapes = [
    { case: "acceptance: s", evidence: "free string", verdict: "pass" },
    { case: "acceptance: s", verdict: "pass" },
    { case: "acceptance: s", evidence: { kind: "command", ref: "x", quote: "" }, verdict: "pass" },
    { case: "acceptance: s", evidence: { kind: "note", ref: "x", quote: "q" }, verdict: "fail" },
    { case: "acceptance: s", evidence: { kind: "command", ref: "", quote: "q" }, verdict: "missing" },
  ];
  for (const shape of shapes) {
    const { host, order } = mockHost({ reads: [handedOff, approved], auditRows: [shape] });
    const result = await workflow(host);
    assert(result.outcome === "audit_failure", "untyped shape audits-fails, got " + result.outcome);
    assert(!order.includes("grade") && !order.includes("verify"), "no verdict emitted for untyped shape");
  }
}

// --- mvp.3 empty-stdout trap: clean porcelain quoted with
// --- the machine token, judged on merits ---
{
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a")] });
  const result = await workflow(host);
  const row = rowNamed(result, "adherence: no hand-edited state");
  assert(row && row.evidence.quote === "(empty stdout, exit 0)", "empty stdout quoted with machine token, got " + (row && row.evidence.quote));
  assert(row.verdict === "pass", "silence is the pass condition");
  assert(result.outcome === "approved", "empty-stdout fixture grades on merits, got " + result.outcome);
}

// --- dirty tree is a real adherence failure and still gates ---
{
  const dirty = { ...GOOD_OBS, git_clean: { stdout: " M dirty.txt\n", exit: 0 } };
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a")], validationsObs: dirty });
  const result = await workflow(host);
  assert(rowNamed(result, "adherence: no hand-edited state").verdict === "fail", "dirty tree fails git-clean validation");
  assert(result.outcome === "needs_fix", "real adherence defect still gates, got " + result.outcome);
}

// --- pure-grade (followup.5): single cast, no verdict race ---
{
  const { host, inputs } = mockHost({
    reads: [handedOff, handedOff, approved],
    auditRows: [passRow("acceptance: a")],
  });
  const result = await workflow(host);
  assert(result.outcome === "approved", "pure grade approves on re-read, got " + result.outcome);
  assert(result.casts === 1, "one cast only, got " + result.casts);
  assert(!result.refusals.some((r) => r.includes("expected verdict race") || r.includes("E_ILLEGAL_EDGE")),
    "verdict-race refusal no longer occurs");
  assert(!inputs.grade.includes("bp3 g " + "toy u") && !inputs.verify.includes("bp3 g " + "toy u"),
    "grade/verify tapes carry no cast (tape grep evidence)");
}

// --- safe replay: killed grade re-dispatched, no partial writes ---
{
  const rows = [passRow("acceptance: a")];
  const first = mockHost({ reads: [handedOff, handedOff, approved], auditRows: rows });
  const r1 = await workflow(first.host);
  const replay = mockHost({ reads: [handedOff, handedOff, approved], auditRows: rows });
  const r2 = await workflow(replay.host);
  assert(r1.casts === 1 && r2.casts === 1, "each dispatch casts once, replay adds no partial writes");
  assert(JSON.stringify(r2.matrix) === JSON.stringify(r1.matrix), "replay returns the same matrix");
  assert(r2.outcome === "approved", "replay approves, got " + r2.outcome);
}

// --- pushback: superseded commit refused by name, no cast ---
{
  const other = { state: "handed_off", cycle: 1, commit: "def5678", legal_edges: ["grade", "verify"] };
  const { host, order } = mockHost({
    reads: [handedOff, other],
    auditRows: [passRow("acceptance: a")],
  });
  const result = await workflow(host);
  assert(result.outcome === "refused", "superseded verdict refused, got " + result.outcome);
  assert(result.casts === 0 && !order.includes("apply"), "no cast attempted for superseded verdict");
  assert(result.refusals.some((r) => r.includes("superseded - re-grade")),
    "superseded pushback named, got " + result.refusals.join(" | "));
}

// --- pushback: empty fix escalates, no author dispatched ---
{
  const { host, order } = mockHost({
    reads: [handedOff, handedOff],
    auditRows: [passRow("acceptance: a")],
    stageReplies: { grade: JSON.stringify({ ok: true, run_id: "r-grade", commit: COMMIT, verdict: "needs_fix", fix: "" }) },
  });
  const result = await workflow(host);
  assert(result.outcome === "escalated", "empty fix escalates, got " + result.outcome);
  assert(result.casts === 0 && !order.includes("apply"), "empty fix casts nothing");
  assert(result.refusals.some((r) => r.includes("empty fix")), "empty-fix pushback named");
}

// --- pushback: blocked read escalates to the owner gate ---
{
  const blocked = { state: "blocked", cycle: 1, commit: COMMIT, legal_edges: ["resume", "delete"] };
  const { host, order } = mockHost({
    reads: [handedOff, blocked],
    auditRows: [passRow("acceptance: a")],
  });
  const result = await workflow(host);
  assert(result.outcome === "escalated", "blocked read escalates, got " + result.outcome);
  assert(result.casts === 0 && !order.includes("apply"), "blocked cast untouched");
  assert(result.refusals.some((r) => r.includes("owner gate")), "blocked pushback named owner gate");
}

// --- fix ledger: needs_fix opens one verbatim entry ---
{
  const fail = passRow("acceptance: a");
  fail.verdict = "fail";
  const { host } = mockHost({
    reads: [handedOff, handedOff, { state: "todo", cycle: 2, commit: COMMIT, legal_edges: ["handoff"] }],
    auditRows: [fail],
    stageReplies: { grade: JSON.stringify({ ok: true, run_id: "r-grade", commit: COMMIT, verdict: "needs_fix", fix: "repair acceptance: a in test/g.sh" }) },
  });
  const result = await workflow(host);
  assert(result.outcome === "needs_fix", "ledger cycle needs_fix, got " + result.outcome);
  assert(result.ledger.length === 1 && result.ledger[0].state === "OPEN" &&
    result.ledger[0].fix === "repair acceptance: a in test/g.sh" && result.ledger[0].commit === COMMIT,
    "OPEN entry carries the fix verbatim + commit, got " + JSON.stringify(result.ledger));
}

// --- mechanical never blocks at/over the cap (followup.5) ---
{
  const fail = passRow("acceptance: a");
  fail.verdict = "fail";
  const atCap = { state: "handed_off", cycle: 5, commit: COMMIT, legal_edges: ["grade", "verify"] };
  const { host, inputs } = mockHost({
    reads: [atCap, atCap, { state: "todo", cycle: 6, commit: COMMIT, legal_edges: ["handoff"] }],
    auditRows: [fail],
    stageReplies: { grade: JSON.stringify({ ok: true, run_id: "r-grade", commit: COMMIT, verdict: "needs_fix", fix: "skills/bp3g/SKILL.md:12 replace GOAL.md with GRAPH.md", fix_class: "mechanical" }) },
  });
  const result = await workflow(host);
  assert(result.outcome === "needs_fix", "mechanical at cap stays needs_fix, got " + result.outcome);
  assert(inputs.apply.includes("--mechanical"), "mechanical cast carries --mechanical");
  assert(result.casts === 1, "mechanical casts once");
}

// --- disagreement counts toward the cap and blocks there ---
{
  const fail = passRow("acceptance: a");
  fail.verdict = "fail";
  const { host, inputs } = mockHost({
    reads: [handedOff, handedOff, { state: "blocked", cycle: 1, commit: COMMIT, legal_edges: ["resume", "delete"] }],
    auditRows: [fail],
    extraArgs: { prior_failed_rows: ["acceptance: a"], max_cycles: 1 },
    stageReplies: { grade: JSON.stringify({ ok: true, run_id: "r-grade", commit: COMMIT, verdict: "needs_fix", fix: "skills/bp3g/SKILL.md:12 replace GOAL.md with GRAPH.md" }) },
  });
  const result = await workflow(host);
  assert(result.verdict.fix_class === "disagreement", "repeat row classed disagreement, got " + result.verdict.fix_class);
  assert(!inputs.apply.includes("--mechanical"), "disagreement cast is not mechanical");
  assert(result.outcome === "blocked", "disagreement blocks at cap, got " + result.outcome);
}

// --- audit reuse (warden #9): prior evidence not re-executed ---
{
  const prior = [{
    case: "acceptance: a", verdict: "pass",
    evidence: { kind: "command", ref: "test/g.sh", quote: "g tests: ok" },
    source: ".git/bp3/20260101T000000Z-fx-validations.log",
  }];
  const reused = passRow("acceptance: a");
  reused.reused_from = ".git/bp3/20260101T000000Z-fx-validations.log";
  const { host, inputs } = mockHost({
    reads: [handedOff, handedOff, approved],
    auditRows: [reused],
    validationsObs: { ...GOOD_OBS, prior_evidence: prior },
  });
  const result = await workflow(host);
  assert(inputs.audit.includes("do not re-execute"), "audit told not to re-execute reused suite");
  assert(inputs.audit.includes(".git/bp3/20260101T000000Z-fx-validations.log"),
    "reuse quotes its source (log path)");
  assert(rowNamed(result, "acceptance: a").reused_from === ".git/bp3/20260101T000000Z-fx-validations.log",
    "reused row keeps its source, never a fresh run");
  const fresh = mockHost({ reads: [handedOff, handedOff, approved], auditRows: [passRow("acceptance: a")] });
  await workflow(fresh.host);
  assert(fresh.inputs.audit.includes("execute every acceptance-named test yourself"),
    "no prior evidence: audit executes as today");
}

// --- run-folder transport variants (followup.1 cycle 2): the
// --- existing handoff folder passes canonical and
// --- prose-shaped lines; a folder missing a file still fails ---
{
  const HANDOFF = "20261117T033939Z-handoff-muse-code-muse-wonder-1.0-c1";
  async function runFolderCase(runFolders) {
    const { host, inputs } = mockHost({
      reads: [handedOff, approved],
      auditRows: [passRow("acceptance: a")],
      validationsObs: { ...GOOD_OBS, run_folders: runFolders },
    });
    const result = await workflow(host);
    return { result, inputs };
  }
  {
    const { result, inputs } = await runFolderCase([HANDOFF + " tape=yes notes=yes"]);
    const row = rowNamed(result, "adherence: run folder present");
    assert(row && row.verdict === "pass" && row.evidence.quote.includes(HANDOFF),
      "canonical line passes the existing handoff folder");
    assert(inputs.validations.includes("for d in"),
      "validations transport carries the run-folder one-liner");
    assert(inputs.validations.includes("never reformat its lines"),
      "validations transport forbids prose reformatting");
  }
  for (const line of [
    HANDOFF + ": tape.log present, notes.md present",
    HANDOFF + " tape: yes, notes: yes",
    HANDOFF + "/ contains tape.log and notes.md",
  ]) {
    const { result } = await runFolderCase([line]);
    assert(rowNamed(result, "adherence: run folder present").verdict === "pass",
      "prose-shaped line passes: " + line);
  }
  {
    const { result } = await runFolderCase(HANDOFF + " tape=yes notes=yes\n20260101T000000Z-verify-muse-code-test-model-c1 tape=yes notes=no");
    assert(rowNamed(result, "adherence: run folder present").verdict === "pass",
      "newline string transport passes");
  }
  for (const bad of [[], [HANDOFF + " tape=yes notes=no"], [HANDOFF + " tape=no notes=yes"],
                     [HANDOFF + ": tape.log present, notes.md missing"]]) {
    const { result } = await runFolderCase(bad);
    assert(rowNamed(result, "adherence: run folder present").verdict === "fail",
      "folder missing a file still fails: " + JSON.stringify(bad));
    assert(result.outcome === "needs_fix", "missing-file folder still gates");
  }
}

// --- workflow-birth: the read carries the desk ---
{
  const { host, inputs } = mockHost({
    reads: [handedOff, approved],
    auditRows: [passRow("acceptance: a"), passRow("adherence: tape present")],
    extraArgs: { desk: ".bp3/worktrees/toy-desk" },
  });
  const result = await workflow(host);
  assert(result.outcome === "approved", "desk grade approves, got " + result.outcome);
  assert(inputs.reads.length > 0, "reads captured, got " + inputs.reads.length);
  for (const read of inputs.reads) {
    assert(read.includes("graph worktree `.bp3/worktrees/toy-desk`"),
      "read prompt names the desk worktree");
    assert(!read.includes("named below"), "read prompt never points below for the desk");
  }
}

if (failures > 0) process.exit(1);
console.log("bp3g-grade tests: ok");
