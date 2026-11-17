// Mock-host test for skills/traverse/workflows/induct-grade.js.
// Covers the exp Acceptance table: typed matrix returned, a
// missing-evidence row blocks approval, an untyped row never
// carries pass, a deferred row naming its owning exp never
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
// with no verdict cast, and a refused parallel cast after
// state moved is a named expected verdict race.
import workflow from "../skills/traverse/workflows/induct-grade.js";

const TS = "20260101T000000Z";
const COMMIT = "abc1234";
let failures = 0;
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); failures++; }
}

function passRow(name) {
  return {
    case: name,
    evidence: { kind: "command", ref: "test/q.sh", quote: "q tests: ok" },
    verdict: "pass",
  };
}

function deferredRow(name) {
  return {
    case: name,
    evidence: {
      kind: "file",
      ref: "docs/quests/toy/experiments/fx/EXPERIMENT.md:57",
      quote: "| " + name + " | NOT gated by this exp |",
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
function mockHost({ reads, auditRows, auditSeq, validationsObs, stageReplies, initFails }) {
  let readIdx = 0;
  let auditIdx = 0;
  const inputs = {};
  const order = [];
  const inits = [];
  const host = {
    args: { quest: "toy", exp: "fx", ts: TS, harness: "muse-code", model: "test-model", commit: COMMIT },
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
      if (input.startsWith("Run exactly")) {
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

// --- grade a handed_off exp: outcome + typed matrix, bindings ---
{
  const { host, inputs, order, inits } = mockHost({
    reads: [handedOff, approved],
    auditRows: [passRow("acceptance: a"), passRow("adherence: tape present")],
  });
  const result = await workflow(host);
  assert(result.outcome === "approved", "all-pass grade approves, got " + result.outcome);
  assert(Array.isArray(result.matrix) && result.matrix.length === 7, "matrix has 5 adherence + 2 acceptance rows, got " + result.matrix.length);
  assert(result.matrix.every((r) => r.verdict === "pass"), "all rows pass");
  assert(order.join(",") === "validations,init,audit,init,init,grade,verify", "validations precede the audit, writer precedes each grade child, got " + order.join(","));
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
  assert(inputs.audit.includes("do not call any `bp3 q u` update edge"),
    "audit child spawns no state edge");
  assert(inputs.audit.includes("notes.md"), "audit writes matrix in its notes.md");
  assert(inputs.audit.includes("acceptance rows only"), "audit builds acceptance rows only");
  assert(!inputs.audit.includes("adherence rows for the build Run"),
    "audit brief no longer asks the LLM for adherence rows");
  assert(inputs.validations.includes("git status --porcelain"),
    "validations transport runs git status --porcelain");
  for (const name of ["adherence: no hand-edited state", "adherence: clean commit", "adherence: run folder present", "adherence: handoff by child", "adherence: env run-id stamped"]) {
    assert(rowNamed(result, name) && rowNamed(result, name).verdict === "pass",
      "validations minted " + name);
  }
  assert(inputs.grade.includes("grade --verdict ship --commit " + COMMIT),
    "grade binds the exact commit");
  assert(inputs.verify.includes("verify --verdict pass --commit " + COMMIT),
    "verify binds the exact commit");
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
  assert(result.outcome === "todo", "todo exp is not graded, got " + result.outcome);
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
    args: { quest: "toy", exp: "fx", ts: TS },
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
      deferredRow("acceptance: full cycle — NOT gated by this exp, deferred to Exp 3"),
    ],
  });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: full cycle — NOT gated by this exp, deferred to Exp 3").verdict === "deferred", "deferred row stays deferred");
  assert(rowNamed(result, "acceptance: full cycle — NOT gated by this exp, deferred to Exp 3").evidence.kind === "file", "deferred row keeps its typed deferral evidence");
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

// --- deferral naming no owning exp is missing, not deferred ---
{
  const unnamed = deferredRow("acceptance: later work — deferred");
  unnamed.evidence.quote = "deferred to a later exp";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), unnamed] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: later work — deferred").verdict === "missing", "unnamed deferral downgraded to missing");
  assert(result.outcome === "needs_fix", "unnamed deferral blocks approval, got " + result.outcome);
}

// --- deferral text naming its owner is deferred even if mislabeled missing ---
{
  const mislabeled = deferredRow("acceptance: full cycle — NOT gated by this exp, deferred to Exp 3");
  mislabeled.verdict = "missing";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), mislabeled] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: full cycle — NOT gated by this exp, deferred to Exp 3").verdict === "deferred", "mislabeled deferral upgraded to deferred");
  assert(result.outcome === "approved", "mislabeled deferral does not block approval, got " + result.outcome);
}

// --- deferred without typed evidence is missing, never deferred ---
{
  const untyped = { case: "acceptance: x — deferred to Exp 3", evidence: "deferred to Exp 3", verdict: "deferred" };
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [untyped] });
  const result = await workflow(host);
  assert(rowNamed(result, "acceptance: x — deferred to Exp 3").verdict === "missing", "untyped deferred downgraded to missing");
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
    if (v === "deferred") return deferredRow("acceptance: d" + i + " — deferred to Exp 3");
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
  assert(inputs.audit.includes("rung 1 the quest and exp records"), "audit starts at rung 1 (records)");
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
  assert(order.join(",") === "validations,init,audit,recollect,init,init,grade,verify",
    "one audit-internal retry, then verdicts, got " + order.join(","));
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

// --- verdict race: sibling moved state, refused cast named ---
{
  const raced = JSON.stringify({ ok: false, error: { code: "E_ILLEGAL_EDGE", facts: { state: "approved" } } });
  const { host } = mockHost({
    reads: [handedOff, approved],
    auditRows: [passRow("acceptance: a")],
    stageReplies: { grade: raced },
  });
  const result = await workflow(host);
  assert(result.outcome === "approved", "raced grade still approves on re-read, got " + result.outcome);
  assert(result.refusals.some((r) => r.includes("expected verdict race") && r.includes("grade") && r.includes("E_ILLEGAL_EDGE")),
    "refused cast reported as an expected verdict race");
}

if (failures > 0) process.exit(1);
console.log("induct-grade tests: ok");
