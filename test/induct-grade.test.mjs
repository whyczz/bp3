// Mock-host test for skills/induct/workflows/induct-grade.js.
// Covers the exp Acceptance table: typed matrix returned, a
// missing-evidence row blocks approval, an untyped row never
// carries pass, a deferred row naming its owning exp never
// blocks (an unnamed or untyped deferral is missing), the
// audit quotes env-preset evidence from the stamped ledger line,
// row order never changes the outcome, replay on the same
// commit returns the same matrix, and grade children are
// judge-only (audit spawns no edge, review/check bind the
// exact commit).
import workflow from "../skills/induct/workflows/induct-grade.js";

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

// reads: state replies in order; audit replies with auditRows;
// review/check reply as cast verdicts. Records stage inputs.
function mockHost({ reads, auditRows }) {
  let readIdx = 0;
  const inputs = {};
  const order = [];
  const host = {
    args: { quest: "toy", exp: "fx", ts: TS, harness: "muse-code", model: "test-model", commit: COMMIT },
    async agent({ label, input }) {
      if (input.startsWith("Run exactly")) {
        return JSON.stringify(reads[Math.min(readIdx++, reads.length - 1)]);
      }
      const edge = label.split(" ")[0];
      inputs[edge] = input;
      order.push(edge);
      if (edge === "audit") {
        return JSON.stringify({ ok: true, run_id: "r-audit", matrix: auditRows });
      }
      return JSON.stringify({ ok: true, run_id: "r-" + edge, commit: COMMIT, verdict: { ok: true } });
    },
    async parallel(calls) {
      const out = [];
      for (const c of calls) out.push(await host.agent(c));
      return out;
    },
  };
  return { host, inputs, order };
}

const submitted = { state: "submitted", cycle: 1, commit: COMMIT, legal_edges: ["review", "check"] };
const approved = { state: "approved", cycle: 1, commit: COMMIT, legal_edges: ["land"] };

// --- grade a submitted exp: outcome + typed matrix, bindings ---
{
  const { host, inputs, order } = mockHost({
    reads: [submitted, approved],
    auditRows: [passRow("acceptance: a"), passRow("adherence: tape present")],
  });
  const result = await workflow(host);
  assert(result.outcome === "approved", "all-pass grade approves, got " + result.outcome);
  assert(Array.isArray(result.matrix) && result.matrix.length === 2, "matrix has both rows");
  assert(result.matrix.every((r) => r.verdict === "pass"), "all rows pass");
  assert(order.join(",") === "audit,review,check", "audit first, then review+check, got " + order.join(","));
  for (const edge of ["audit", "review", "check"]) {
    const input = inputs[edge];
    assert(input, edge + " child was spawned");
    const want = "BP3_RUN_ID=" + TS + "-" + edge + "-muse-code-test-model-c1";
    assert(input.includes(want), edge + " command carries " + want);
    assert(input.includes("runs/" + TS + "-" + edge + "-muse-code-test-model-c1"),
      edge + " run folder matches BP3_RUN_ID");
  }
  assert(inputs.audit.includes("do not call any `bp3 q u` update edge"),
    "audit child spawns no state edge");
  assert(inputs.audit.includes("notes.md"), "audit writes matrix in its notes.md");
  assert(inputs.review.includes("review --verdict ship --commit " + COMMIT),
    "review binds the exact commit");
  assert(inputs.check.includes("check --verdict pass --commit " + COMMIT),
    "check binds the exact commit");
  assert(result.run_ids.join(",") === "r-audit,r-review,r-check",
    "run_ids collect every grade child, got " + result.run_ids.join(","));
}

// --- no artifact: row missing, outcome cannot be approved ---
{
  const missing = passRow("acceptance: b");
  missing.verdict = "missing";
  const { host } = mockHost({ reads: [submitted, approved], auditRows: [passRow("acceptance: a"), missing] });
  const result = await workflow(host);
  assert(result.matrix[1].verdict === "missing", "missing row stays missing");
  assert(result.outcome === "needs_fix", "missing row blocks approval, got " + result.outcome);
}

// --- untyped evidence never carries pass; free string is not a row ---
{
  const untyped = { case: "acceptance: c", evidence: "looked fine", verdict: "pass" };
  const { host } = mockHost({ reads: [submitted, approved], auditRows: [untyped] });
  const result = await workflow(host);
  assert(result.matrix[0].verdict === "missing", "untyped pass downgraded to missing");
  assert(result.outcome === "needs_fix", "untyped row blocks approval, got " + result.outcome);
}

// --- row order never changes the outcome ---
{
  const fail = passRow("acceptance: d");
  fail.verdict = "fail";
  const a = mockHost({ reads: [submitted, approved], auditRows: [passRow("acceptance: a"), fail] });
  const b = mockHost({ reads: [submitted, approved], auditRows: [fail, passRow("acceptance: a")] });
  const ra = await workflow(a.host);
  const rb = await workflow(b.host);
  assert(ra.outcome === rb.outcome && ra.outcome === "needs_fix",
    "row order keeps outcome, got " + ra.outcome + "/" + rb.outcome);
}

// --- replay on the same commit: same matrix, still approved ---
{
  const rows = [passRow("acceptance: a")];
  const first = mockHost({ reads: [submitted, approved], auditRows: rows });
  const r1 = await workflow(first.host);
  const replay = mockHost({ reads: [approved, approved], auditRows: rows });
  const r2 = await workflow(replay.host);
  assert(r2.outcome === "approved", "replay on approved commit approves, got " + r2.outcome);
  assert(JSON.stringify(r2.matrix) === JSON.stringify(r1.matrix), "replay returns the same matrix");
}

// --- not submitted: no grade children spawn ---
{
  const todo = { state: "todo", cycle: 1, commit: null, legal_edges: ["submit"] };
  const { host, order } = mockHost({ reads: [todo], auditRows: [passRow("acceptance: a")] });
  const result = await workflow(host);
  assert(result.outcome === "todo", "todo exp is not graded, got " + result.outcome);
  assert(order.length === 0, "no grade children spawn for todo");
}

// --- commit mismatch and missing args refuse without children ---
{
  const other = { state: "submitted", cycle: 1, commit: "def5678", legal_edges: ["review", "check"] };
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
    reads: [submitted, approved],
    auditRows: [
      passRow("acceptance: a"),
      deferredRow("acceptance: full cycle — NOT gated by this exp, deferred to Exp 3"),
    ],
  });
  const result = await workflow(host);
  assert(result.matrix[1].verdict === "deferred", "deferred row stays deferred");
  assert(result.matrix[1].evidence.kind === "file", "deferred row keeps its typed deferral evidence");
  assert(result.outcome === "approved", "deferred row does not block approval, got " + result.outcome);
  assert(inputs.audit.includes("verdict: pass|fail|missing|deferred"),
    "audit may emit deferred rows");
  assert(!inputs.audit.includes("bp3-run-registry"),
    "audit never names the retired run registry");
  assert(inputs.audit.includes("run-lifecycle-derivations"),
    "audit corroborates from the per-Run derivation log");
  assert(inputs.audit.includes("stamped"), "audit quotes the stamped ledger line");
  assert(inputs.review.includes("deferred"), "review is told deferred rows never block");
  assert(inputs.check.includes("deferred"), "check is told deferred rows never block");
}

// --- deferral naming no owning exp is missing, not deferred ---
{
  const unnamed = deferredRow("acceptance: later work — deferred");
  unnamed.evidence.quote = "deferred to a later exp";
  const { host } = mockHost({ reads: [submitted, approved], auditRows: [passRow("acceptance: a"), unnamed] });
  const result = await workflow(host);
  assert(result.matrix[1].verdict === "missing", "unnamed deferral downgraded to missing");
  assert(result.outcome === "needs_fix", "unnamed deferral blocks approval, got " + result.outcome);
}

// --- deferral text naming its owner is deferred even if mislabeled missing ---
{
  const mislabeled = deferredRow("acceptance: full cycle — NOT gated by this exp, deferred to Exp 3");
  mislabeled.verdict = "missing";
  const { host } = mockHost({ reads: [submitted, approved], auditRows: [passRow("acceptance: a"), mislabeled] });
  const result = await workflow(host);
  assert(result.matrix[1].verdict === "deferred", "mislabeled deferral upgraded to deferred");
  assert(result.outcome === "approved", "mislabeled deferral does not block approval, got " + result.outcome);
}

// --- deferred without typed evidence is missing, never deferred ---
{
  const untyped = { case: "acceptance: x — deferred to Exp 3", evidence: "deferred to Exp 3", verdict: "deferred" };
  const { host } = mockHost({ reads: [submitted, approved], auditRows: [untyped] });
  const result = await workflow(host);
  assert(result.matrix[0].verdict === "missing", "untyped deferred downgraded to missing");
  assert(result.outcome === "needs_fix", "untyped deferred blocks approval, got " + result.outcome);
}

// --- verdict outside pass|fail|missing|deferred is coerced ---
{
  const bogus = passRow("acceptance: e");
  bogus.verdict = "bogus";
  const { host } = mockHost({ reads: [submitted, approved], auditRows: [bogus] });
  const result = await workflow(host);
  assert(result.matrix[0].verdict === "missing", "unknown verdict coerced to missing");
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
    const { host } = mockHost({ reads: [submitted, approved], auditRows: rows });
    return (await workflow(host)).outcome;
  }
  const seqs = [[]];
  for (let len = 1; len <= 3; len++) {
    const prev = seqs.filter((s) => s.length === len - 1);
    for (const p of prev) for (const k of kinds) seqs.push(p.concat(k));
  }
  for (const seq of seqs) {
    const got = await outcomeOf(seq.map(rowFor));
    const gatedBad = seq.length === 0 || seq.some((v) => v !== "pass" && v !== "deferred");
    const want = gatedBad ? "needs_fix" : "approved";
    assert(got === want, "outcome for [" + seq.join(",") + "] is " + want + ", got " + got);
    const rev = await outcomeOf(seq.slice().reverse().map(rowFor));
    assert(rev === got, "row order keeps outcome for [" + seq.join(",") + "]");
  }
}

if (failures > 0) process.exit(1);
console.log("induct-grade tests: ok");
