// Mock-host test for skills/induct/workflows/induct-grade.js.
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
// and verify children return verdicts as data (zero `bp3 q u`
// calls); the looper applies exactly one combined cast, with
// named pushbacks (superseded, empty fix, blocked), a fix
// ledger OPEN entry, audit reuse of prior typed evidence,
// and a named mechanical fix that never blocks while the
// cycle cap counts disagreement cycles only.
import { test } from "node:test";
import assert from "node:assert/strict";
import workflow from "../skills/induct/workflows/induct-grade.js";

const TS = "20260101T000000Z";
const COMMIT = "abc1234";

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
      ref: "docs/quests/toy/nodes/fx/NODE.md:57",
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
    args: Object.assign({ quest: "toy", node: "fx", ts: TS, harness: "muse-code", model: "test-model", commit: COMMIT }, extraArgs || {}),
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
test("grade a handed_off node: outcome + typed matrix, bindings", async () => {
  const { host, inputs, order, inits } = mockHost({
    reads: [handedOff, approved],
    auditRows: [passRow("acceptance: a"), passRow("adherence: tape present")],
  });
  const result = await workflow(host);
  assert.ok(result.outcome === "approved", "all-pass grade approves, got " + result.outcome);
  assert.ok(Array.isArray(result.matrix) && result.matrix.length === 7, "matrix has 5 adherence + 2 acceptance rows, got " + result.matrix.length);
  assert.ok(result.matrix.every((r) => r.verdict === "pass"), "all rows pass");
  assert.ok(order.join(",") === "validations,init,audit,init,init,grade,verify,apply", "validations precede the audit, writer precedes each pure child, looper applies last, got " + order.join(","));
  assert.ok(result.casts === 1, "exactly one verdict cast per grade, got " + result.casts);
  assert.ok(result.verdict && result.verdict.outcome === "ship", "pure verdict is ship data");
  assert.ok(Array.isArray(result.ledger) && result.ledger.length === 0, "ship opens no fix ledger entry");
  assert.ok(inits.join(",") === [TS + "-audit-muse-code-test-model-c1", TS + "-grade-muse-code-test-model-c1", TS + "-verify-muse-code-test-model-c1"].join(","),
    "mints name every grade run-id, got " + inits.join(","));
  for (const edge of ["audit", "grade", "verify"]) {
    const input = inputs[edge];
    assert.ok(input, edge + " child was spawned");
    assert.ok(input.includes("runs/" + TS + "-" + edge + "-muse-code-test-model-c1"),
      edge + " run folder matches the minted run-id");
    assert.ok(!input.includes("Prefix your FIRST"),
      edge + " brief carries no first-command prefix instruction");
    assert.ok(input.includes("arrives via the"),
      edge + " is told the run-id arrives via the claim");
  }
  for (const edge of ["grade", "verify"]) {
    assert.ok(inputs[edge].includes("link claim bp3link_test-" + edge), edge + " brief carries its claim token");
    assert.ok(inputs[edge].includes("BP3_RUN_ID=<that run_id>"), edge + " is told to stamp the claimed run-id");
  }
  assert.ok(inputs.audit.includes("do not call any `bp3 q u` update edge"),
    "audit child spawns no state edge");
  assert.ok(inputs.audit.includes("notes.md"), "audit writes matrix in its notes.md");
  assert.ok(inputs.audit.includes("acceptance rows only"), "audit builds acceptance rows only");
  assert.ok(!inputs.audit.includes("adherence rows for the build Run"),
    "audit brief no longer asks the LLM for adherence rows");
  assert.ok(inputs.validations.includes("git status --porcelain"),
    "validations transport runs git status --porcelain");
  assert.ok(inputs.validations.includes("shell moves the bytes, you move a pointer"),
    "validations transport is pointer-contracted (log file, not verbatim JSON)");
  assert.ok(inputs.validations.includes("-validations.log"),
    "validations transport writes the .git/bp3 validations log");
  assert.ok(inputs.validations.includes("git show --stat " + COMMIT + " | head -3"),
    "validations transport bounds git_show to its head for the JSON return");
  assert.ok(inputs.validations.includes("git show bp3/node/toy/fx:docs/quests/toy/nodes/fx/ledger.jsonl"),
    "validations probe resolves the handoff ledger via the post-migration node branch");
  assert.ok(!inputs.validations.includes("bp3/exp/"),
    "validations probe carries no retired bp3/exp hardcode");
  for (const name of ["adherence: no hand-edited state", "adherence: clean commit", "adherence: run folder present", "adherence: handoff by child", "adherence: env run-id stamped"]) {
    assert.ok(rowNamed(result, name) && rowNamed(result, name).verdict === "pass",
      "validations minted " + name);
  }
  for (const edge of ["grade", "verify"]) {
    assert.ok(inputs[edge].includes("do not call any `bp3 q u` update edge"),
      edge + " child is pure (zero bp3 q u calls)");
    assert.ok(inputs[edge].includes("return your verdict as data") ||
           inputs[edge].includes("Return your verdict as data"),
      edge + " child returns its verdict as data");
    assert.ok(!inputs[edge].includes("u fx " + edge + " --verdict"),
      edge + " brief carries no cast command");
    assert.ok(inputs[edge].includes(COMMIT), edge + " judges the exact bound commit");
  }
  assert.ok(inputs.apply.includes("grade --verdict ship --commit " + COMMIT + " --verify-verdict pass"),
    "looper's one cast binds the exact commit with the combined verdict");
  assert.ok((inputs.apply.match(/bp3 q /g) || []).length === 1,
    "looper apply runs exactly one bp3 command");
  assert.ok(result.run_ids.join(",") === [TS + "-audit-muse-code-test-model-c1", "r-audit", TS + "-grade-muse-code-test-model-c1", TS + "-verify-muse-code-test-model-c1", "r-grade", "r-verify"].join(","),
    "run_ids collect mints and every grade child, got " + result.run_ids.join(","));
});

// --- no artifact: row missing, outcome cannot be approved ---
test("no artifact: row missing, outcome cannot be approved", async () => {
  const missing = passRow("acceptance: b");
  missing.verdict = "missing";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), missing] });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: b").verdict === "missing", "missing row stays missing");
  assert.ok(result.outcome === "needs_fix", "missing row blocks approval, got " + result.outcome);
});

// --- untyped evidence never reaches the FSM; still untyped
// --- after one re-collect it is an explicit audit failure ---
test("untyped evidence never reaches the FSM; still untyped after one re-collect it is an explicit audit failure", async () => {
  const untyped = { case: "acceptance: c", evidence: "looked fine", verdict: "pass" };
  const { host, order } = mockHost({ reads: [handedOff, approved], auditRows: [untyped] });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: c").verdict === "missing", "untyped pass downgraded to missing");
  assert.ok(result.outcome === "audit_failure", "untyped row is an audit failure, got " + result.outcome);
  assert.ok(result.outcome !== "needs_fix", "audit failure is distinguishable from needs_fix");
  assert.ok(order.includes("recollect"), "audit re-collected the named row, got " + order.join(","));
  assert.ok(!order.includes("grade") && !order.includes("verify"), "no verdict cast on untyped evidence");
  assert.ok(result.refusals.some((r) => r.includes("audit failure") && r.includes("acceptance: c") && r.includes("collection error")),
    "audit failure names the row and the collection error");
});

// --- row order never changes the outcome ---
test("row order never changes the outcome", async () => {
  const fail = passRow("acceptance: d");
  fail.verdict = "fail";
  const a = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), fail] });
  const b = mockHost({ reads: [handedOff, approved], auditRows: [fail, passRow("acceptance: a")] });
  const ra = await workflow(a.host);
  const rb = await workflow(b.host);
  assert.ok(ra.outcome === rb.outcome && ra.outcome === "needs_fix",
    "row order keeps outcome, got " + ra.outcome + "/" + rb.outcome);
});

// --- replay on the same commit: same matrix, still approved ---
test("replay on the same commit: same matrix, still approved", async () => {
  const rows = [passRow("acceptance: a")];
  const first = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const r1 = await workflow(first.host);
  const replay = mockHost({ reads: [approved, approved], auditRows: rows });
  const r2 = await workflow(replay.host);
  assert.ok(r2.outcome === "approved", "replay on approved commit approves, got " + r2.outcome);
  assert.ok(JSON.stringify(r2.matrix) === JSON.stringify(r1.matrix), "replay returns the same matrix");
});

// --- not handed_off: no grade children spawn ---
test("not handed_off: no grade children spawn", async () => {
  const todo = { state: "todo", cycle: 1, commit: null, legal_edges: ["handoff"] };
  const { host, order } = mockHost({ reads: [todo], auditRows: [passRow("acceptance: a")] });
  const result = await workflow(host);
  assert.ok(result.outcome === "todo", "todo node is not graded, got " + result.outcome);
  assert.ok(order.length === 0, "no grade children spawn for todo");
});

// --- commit mismatch and missing args refuse without children ---
test("commit mismatch and missing args refuse without children", async () => {
  const other = { state: "handed_off", cycle: 1, commit: "def5678", legal_edges: ["grade", "verify"] };
  const { host, order } = mockHost({ reads: [other], auditRows: [passRow("acceptance: a")] });
  const result = await workflow(host);
  assert.ok(result.outcome === "refused", "commit mismatch refuses, got " + result.outcome);
  assert.ok(order.length === 0, "no grade children spawn on mismatch");

  const noCommit = {
    args: { quest: "toy", node: "fx", ts: TS },
    async agent() { throw new Error("must not spawn"); },
    async parallel() { throw new Error("must not spawn"); },
  };
  const refused = await workflow(noCommit);
  assert.ok(refused.outcome === "refused", "missing commit refuses");
});

// --- deferred row: owned elsewhere, excluded from the gate ---
test("deferred row: owned elsewhere, excluded from the gate", async () => {
  const { host, inputs } = mockHost({
    reads: [handedOff, approved],
    auditRows: [
      passRow("acceptance: a"),
      deferredRow("acceptance: full cycle — NOT gated by this node, deferred to Node 3"),
    ],
  });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: full cycle — NOT gated by this node, deferred to Node 3").verdict === "deferred", "deferred row stays deferred");
  assert.ok(rowNamed(result, "acceptance: full cycle — NOT gated by this node, deferred to Node 3").evidence.kind === "file", "deferred row keeps its typed deferral evidence");
  assert.ok(result.outcome === "approved", "deferred row does not block approval, got " + result.outcome);
  assert.ok(inputs.audit.includes("verdict: pass|fail|missing|deferred"),
    "audit may emit deferred rows");
  assert.ok(!inputs.audit.includes("bp3-run-registry"),
    "audit never names the retired run registry");
  assert.ok(inputs.audit.includes("run-lifecycle-derivations"),
    "audit corroborates from the per-Run derivation log");
  assert.ok(inputs.audit.includes("stamped"), "audit quotes the stamped ledger line");
  assert.ok(inputs.grade.includes("deferred"), "grade is told deferred rows never block");
  assert.ok(inputs.verify.includes("deferred"), "verify is told deferred rows never block");
});

// --- deferral naming no owning node is missing, not deferred ---
test("deferral naming no owning node is missing, not deferred", async () => {
  const unnamed = deferredRow("acceptance: later work — deferred");
  unnamed.evidence.quote = "deferred to a later node";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), unnamed] });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: later work — deferred").verdict === "missing", "unnamed deferral downgraded to missing");
  assert.ok(result.outcome === "needs_fix", "unnamed deferral blocks approval, got " + result.outcome);
});

// --- deferral text naming its owner is deferred even if mislabeled missing ---
test("deferral text naming its owner is deferred even if mislabeled missing", async () => {
  const mislabeled = deferredRow("acceptance: full cycle — NOT gated by this node, deferred to Node 3");
  mislabeled.verdict = "missing";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a"), mislabeled] });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: full cycle — NOT gated by this node, deferred to Node 3").verdict === "deferred", "mislabeled deferral upgraded to deferred");
  assert.ok(result.outcome === "approved", "mislabeled deferral does not block approval, got " + result.outcome);
});

// --- deferred without typed evidence is missing, never deferred ---
test("deferred without typed evidence is missing, never deferred", async () => {
  const untyped = { case: "acceptance: x — deferred to Node 3", evidence: "deferred to Node 3", verdict: "deferred" };
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [untyped] });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: x — deferred to Node 3").verdict === "missing", "untyped deferred downgraded to missing");
  assert.ok(result.outcome === "audit_failure", "untyped deferred is an audit failure, got " + result.outcome);
});

// --- verdict outside pass|fail|missing|deferred is coerced ---
test("verdict outside pass|fail|missing|deferred is coerced", async () => {
  const bogus = passRow("acceptance: e");
  bogus.verdict = "bogus";
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [bogus] });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: e").verdict === "missing", "unknown verdict coerced to missing");
  assert.ok(result.outcome === "needs_fix", "coerced row blocks approval, got " + result.outcome);
});

// --- generated matrices: order never matters, deferred never gates ---
test("generated matrices: order never matters, deferred never gates", async () => {
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
    assert.ok(got === want, "outcome for [" + seq.join(",") + "] is " + want + ", got " + got);
    const rev = await outcomeOf(seq.slice().reverse().map(rowFor));
    assert.ok(rev === got, "row order keeps outcome for [" + seq.join(",") + "]");
  }
});

// --- evidence ladder (mvp.7): prompts climb rungs in order ---
test("evidence ladder (mvp.7): prompts climb rungs in order", async () => {
  const { host, inputs } = mockHost({
    reads: [handedOff, approved],
    auditRows: [passRow("acceptance: a")],
  });
  await workflow(host);
  assert.ok(inputs.audit.includes("rung 1 the quest and node records"), "audit starts at rung 1 (records)");
  assert.ok(inputs.audit.includes("rung 2 committed code and git diff"), "audit climbs to rung 2 (diff)");
  assert.ok(inputs.audit.includes("rung 3 demos and tests, run"), "audit climbs to rung 3 (tests run)");
  assert.ok(inputs.audit.includes("rung 4 style"), "audit climbs to rung 4 (style)");
  assert.ok(inputs.audit.includes("bp3 harness find-tape --run-id <run-id> --entry"), "audit resolves pointers via find-tape --entry");
  assert.ok(inputs.audit.includes("rung 5b the whole tape, escalation only when blocked, confused, or lying"), "whole tape is named escalation only");
  assert.ok(inputs.audit.includes("zero whole-log reads"), "clean grade shows zero whole-log reads");
  assert.ok(inputs.audit.includes("rung: 1|2|3|4|5a|5b"), "rows name the rung that decided them");
  assert.ok(inputs.grade.includes("find-tape --run-id"), "grade is told the ladder");
  assert.ok(inputs.verify.includes("find-tape --run-id"), "verify is told the ladder");
  assert.ok(inputs.grade.includes("unnamed whole-tape read"), "grade gates unnamed whole-tape reads");
  assert.ok(inputs.verify.includes("unnamed whole-tape read"), "verify gates unnamed whole-tape reads");
});

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
test("lying fixture: rungs 1-4 clean, rung 5a pointer contradicts", async () => {
  const rows = [
    rungRow("acceptance: records", "1", "pass"),
    rungRow("acceptance: diff clean", "2", "pass"),
    rungRow("acceptance: tests pass", "3", "pass"),
    rungRow("acceptance: style", "4", "pass"),
    rungRow("acceptance: claim holds", "5a", "fail", "entry E contradicts the claim"),
  ];
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const result = await workflow(host);
  assert.ok(result.outcome === "needs_fix", "lying fixture blocks, got " + result.outcome);
  assert.ok(rowNamed(result, "acceptance: claim holds").verdict === "fail", "pointer row stays fail");
  assert.ok(rowNamed(result, "acceptance: claim holds").rung === "5a", "pointer row keeps rung 5a");
  assert.ok(rowNamed(result, "acceptance: claim holds").evidence.ref.includes("find-tape --run-id"), "block cites the rung-5 pointer");
});

// --- clean fixture: decided at rungs 1-4, zero whole-log reads ---
test("clean fixture: decided at rungs 1-4, zero whole-log reads", async () => {
  const rows = [
    rungRow("acceptance: records", "1", "pass"),
    rungRow("acceptance: diff clean", "2", "pass"),
    rungRow("acceptance: tests pass", "3", "pass"),
    rungRow("acceptance: style", "4", "pass"),
  ];
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const result = await workflow(host);
  assert.ok(result.outcome === "approved", "clean fixture approves, got " + result.outcome);
  assert.ok(result.matrix.every((r) => r.rung !== "5b"), "clean trace shows zero whole-log reads");
});

// --- confused fixture: named whole-tape escalation is allowed ---
test("confused fixture: named whole-tape escalation is allowed", async () => {
  const rows = [
    rungRow("acceptance: records", "1", "pass"),
    rungRow("acceptance: whole tape decides", "5b", "pass", "confused grade: rungs 1-5a undecided, whole tape read"),
  ];
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: whole tape decides").verdict === "pass", "named escalation keeps its verdict");
  assert.ok(rowNamed(result, "acceptance: whole tape decides").rung === "5b", "escalation row keeps rung 5b");
  assert.ok(result.outcome === "approved", "named confused escalation can decide, got " + result.outcome);
});

// --- unnamed whole-tape read never carries a grade ---
test("unnamed whole-tape read never carries a grade", async () => {
  const rows = [
    rungRow("acceptance: records", "1", "pass"),
    rungRow("acceptance: tape looked fine", "5b", "pass", "read the whole tape"),
  ];
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: rows });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: tape looked fine").verdict === "missing", "unnamed whole-tape pass downgraded to missing");
  assert.ok(result.outcome === "needs_fix", "unnamed whole-tape read blocks approval, got " + result.outcome);
});

// --- a rung outside the ladder is no rung ---
test("a rung outside the ladder is no rung", async () => {
  const bogus = rungRow("acceptance: records", "9", "pass");
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [bogus] });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "acceptance: records").rung === null, "unknown rung coerced to null");
  assert.ok(rowNamed(result, "acceptance: records").verdict === "pass", "row still judged on its typed evidence");
});

// --- writer refused: no grade child starts (mvp.8) ---
test("writer refused: no grade child starts (mvp.8)", async () => {
  const { host, order } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a")], initFails: true });
  const result = await workflow(host);
  assert.ok(result.outcome === "refused", "writer refusal refuses the grade, got " + result.outcome);
  assert.ok(order.join(",") === "validations,init", "no grade child spawns after a refused mint, got " + order.join(","));
  assert.ok(result.refusals.some((r) => r.includes("link mint")), "refusal names link mint");
});

// --- config.1 replay: lazy audit, green product, re-collect
// --- approves with no extra mint and no cycle burn ---
test("config.1 replay: lazy audit, green product, re-collect approves with no extra mint and no cycle burn", async () => {
  const lazy = { case: "acceptance: a", evidence: "looked fine", verdict: "pass" };
  const { host, inputs, order, inits } = mockHost({
    reads: [handedOff, approved],
    auditSeq: [[lazy], [passRow("acceptance: a")]],
  });
  const result = await workflow(host);
  assert.ok(result.outcome === "approved", "re-collected grade approves, got " + result.outcome);
  assert.ok(inputs.recollect && inputs.recollect.includes("acceptance: a"), "re-collect names the untyped row");
  assert.ok(inits.length === 3, "audit retry mints no new link, got " + inits.join(","));
  assert.ok(order.join(",") === "validations,init,audit,recollect,init,init,grade,verify,apply",
    "one audit-internal retry, then pure verdicts and one cast, got " + order.join(","));
  assert.ok(result.matrix.every((r) => r.evidence && typeof r.evidence.quote === "string" && r.evidence.quote !== ""),
    "every judged row carries typed evidence");
});

// --- property: no verdict is emitted while a row lacks
// --- typed evidence, over evidence shapes ---
test("property: no verdict is emitted while a row lacks typed evidence, over evidence shapes", async () => {
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
    assert.ok(result.outcome === "audit_failure", "untyped shape audits-fails, got " + result.outcome);
    assert.ok(!order.includes("grade") && !order.includes("verify"), "no verdict emitted for untyped shape");
  }
});

// --- mvp.3 empty-stdout trap: clean porcelain quoted with
// --- the machine token, judged on merits ---
test("mvp.3 empty-stdout trap: clean porcelain quoted with the machine token, judged on merits", async () => {
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a")] });
  const result = await workflow(host);
  const row = rowNamed(result, "adherence: no hand-edited state");
  assert.ok(row && row.evidence.quote === "(empty stdout, exit 0)", "empty stdout quoted with machine token, got " + (row && row.evidence.quote));
  assert.ok(row.verdict === "pass", "silence is the pass condition");
  assert.ok(result.outcome === "approved", "empty-stdout fixture grades on merits, got " + result.outcome);
});

// --- dirty tree is a real adherence failure and still gates ---
test("dirty tree is a real adherence failure and still gates", async () => {
  const dirty = { ...GOOD_OBS, git_clean: { stdout: " M dirty.txt\n", exit: 0 } };
  const { host } = mockHost({ reads: [handedOff, approved], auditRows: [passRow("acceptance: a")], validationsObs: dirty });
  const result = await workflow(host);
  assert.ok(rowNamed(result, "adherence: no hand-edited state").verdict === "fail", "dirty tree fails git-clean validation");
  assert.ok(result.outcome === "needs_fix", "real adherence defect still gates, got " + result.outcome);
});

// --- pure-grade (followup.5): single cast, no verdict race ---
test("pure-grade (followup.5): single cast, no verdict race", async () => {
  const { host, inputs } = mockHost({
    reads: [handedOff, handedOff, approved],
    auditRows: [passRow("acceptance: a")],
  });
  const result = await workflow(host);
  assert.ok(result.outcome === "approved", "pure grade approves on re-read, got " + result.outcome);
  assert.ok(result.casts === 1, "one cast only, got " + result.casts);
  assert.ok(!result.refusals.some((r) => r.includes("expected verdict race") || r.includes("E_ILLEGAL_EDGE")),
    "verdict-race refusal no longer occurs");
  assert.ok(!inputs.grade.includes("bp3 q " + "toy u") && !inputs.verify.includes("bp3 q " + "toy u"),
    "grade/verify tapes carry no cast (tape grep evidence)");
});

// --- safe replay: killed grade re-dispatched, no partial writes ---
test("safe replay: killed grade re-dispatched, no partial writes", async () => {
  const rows = [passRow("acceptance: a")];
  const first = mockHost({ reads: [handedOff, handedOff, approved], auditRows: rows });
  const r1 = await workflow(first.host);
  const replay = mockHost({ reads: [handedOff, handedOff, approved], auditRows: rows });
  const r2 = await workflow(replay.host);
  assert.ok(r1.casts === 1 && r2.casts === 1, "each dispatch casts once, replay adds no partial writes");
  assert.ok(JSON.stringify(r2.matrix) === JSON.stringify(r1.matrix), "replay returns the same matrix");
  assert.ok(r2.outcome === "approved", "replay approves, got " + r2.outcome);
});

// --- pushback: superseded commit refused by name, no cast ---
test("pushback: superseded commit refused by name, no cast", async () => {
  const other = { state: "handed_off", cycle: 1, commit: "def5678", legal_edges: ["grade", "verify"] };
  const { host, order } = mockHost({
    reads: [handedOff, other],
    auditRows: [passRow("acceptance: a")],
  });
  const result = await workflow(host);
  assert.ok(result.outcome === "refused", "superseded verdict refused, got " + result.outcome);
  assert.ok(result.casts === 0 && !order.includes("apply"), "no cast attempted for superseded verdict");
  assert.ok(result.refusals.some((r) => r.includes("superseded - re-grade")),
    "superseded pushback named, got " + result.refusals.join(" | "));
});

// --- pushback: empty fix escalates, no author dispatched ---
test("pushback: empty fix escalates, no author dispatched", async () => {
  const { host, order } = mockHost({
    reads: [handedOff, handedOff],
    auditRows: [passRow("acceptance: a")],
    stageReplies: { grade: JSON.stringify({ ok: true, run_id: "r-grade", commit: COMMIT, verdict: "needs_fix", fix: "" }) },
  });
  const result = await workflow(host);
  assert.ok(result.outcome === "escalated", "empty fix escalates, got " + result.outcome);
  assert.ok(result.casts === 0 && !order.includes("apply"), "empty fix casts nothing");
  assert.ok(result.refusals.some((r) => r.includes("empty fix")), "empty-fix pushback named");
});

// --- pushback: blocked read escalates to the owner gate ---
test("pushback: blocked read escalates to the owner gate", async () => {
  const blocked = { state: "blocked", cycle: 1, commit: COMMIT, legal_edges: ["resume", "delete"] };
  const { host, order } = mockHost({
    reads: [handedOff, blocked],
    auditRows: [passRow("acceptance: a")],
  });
  const result = await workflow(host);
  assert.ok(result.outcome === "escalated", "blocked read escalates, got " + result.outcome);
  assert.ok(result.casts === 0 && !order.includes("apply"), "blocked cast untouched");
  assert.ok(result.refusals.some((r) => r.includes("owner gate")), "blocked pushback named owner gate");
});

// --- fix ledger: needs_fix opens one verbatim entry ---
test("fix ledger: needs_fix opens one verbatim entry", async () => {
  const fail = passRow("acceptance: a");
  fail.verdict = "fail";
  const { host } = mockHost({
    reads: [handedOff, handedOff, { state: "todo", cycle: 2, commit: COMMIT, legal_edges: ["handoff"] }],
    auditRows: [fail],
    stageReplies: { grade: JSON.stringify({ ok: true, run_id: "r-grade", commit: COMMIT, verdict: "needs_fix", fix: "repair acceptance: a in test/g.sh" }) },
  });
  const result = await workflow(host);
  assert.ok(result.outcome === "needs_fix", "ledger cycle needs_fix, got " + result.outcome);
  assert.ok(result.ledger.length === 1 && result.ledger[0].state === "OPEN" &&
    result.ledger[0].fix === "repair acceptance: a in test/g.sh" && result.ledger[0].commit === COMMIT,
    "OPEN entry carries the fix verbatim + commit, got " + JSON.stringify(result.ledger));
});

// --- mechanical never blocks at/over the cap (followup.5) ---
test("mechanical never blocks at/over the cap (followup.5)", async () => {
  const fail = passRow("acceptance: a");
  fail.verdict = "fail";
  const atCap = { state: "handed_off", cycle: 5, commit: COMMIT, legal_edges: ["grade", "verify"] };
  const { host, inputs } = mockHost({
    reads: [atCap, atCap, { state: "todo", cycle: 6, commit: COMMIT, legal_edges: ["handoff"] }],
    auditRows: [fail],
    stageReplies: { grade: JSON.stringify({ ok: true, run_id: "r-grade", commit: COMMIT, verdict: "needs_fix", fix: "skills/induct/SKILL.md:12 replace GOAL.md with QUEST.md", fix_class: "mechanical" }) },
  });
  const result = await workflow(host);
  assert.ok(result.outcome === "needs_fix", "mechanical at cap stays needs_fix, got " + result.outcome);
  assert.ok(inputs.apply.includes("--mechanical"), "mechanical cast carries --mechanical");
  assert.ok(result.casts === 1, "mechanical casts once");
});

// --- disagreement counts toward the cap and blocks there ---
test("disagreement counts toward the cap and blocks there", async () => {
  const fail = passRow("acceptance: a");
  fail.verdict = "fail";
  const { host, inputs } = mockHost({
    reads: [handedOff, handedOff, { state: "blocked", cycle: 1, commit: COMMIT, legal_edges: ["resume", "delete"] }],
    auditRows: [fail],
    extraArgs: { prior_failed_rows: ["acceptance: a"], max_cycles: 1 },
    stageReplies: { grade: JSON.stringify({ ok: true, run_id: "r-grade", commit: COMMIT, verdict: "needs_fix", fix: "skills/induct/SKILL.md:12 replace GOAL.md with QUEST.md" }) },
  });
  const result = await workflow(host);
  assert.ok(result.verdict.fix_class === "disagreement", "repeat row classed disagreement, got " + result.verdict.fix_class);
  assert.ok(!inputs.apply.includes("--mechanical"), "disagreement cast is not mechanical");
  assert.ok(result.outcome === "blocked", "disagreement blocks at cap, got " + result.outcome);
});

// --- audit reuse (warden #9): prior evidence not re-executed ---
test("audit reuse (warden #9): prior evidence not re-executed", async () => {
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
  assert.ok(inputs.audit.includes("do not re-execute"), "audit told not to re-execute reused suite");
  assert.ok(inputs.audit.includes(".git/bp3/20260101T000000Z-fx-validations.log"),
    "reuse quotes its source (log path)");
  assert.ok(rowNamed(result, "acceptance: a").reused_from === ".git/bp3/20260101T000000Z-fx-validations.log",
    "reused row keeps its source, never a fresh run");
  const fresh = mockHost({ reads: [handedOff, handedOff, approved], auditRows: [passRow("acceptance: a")] });
  await workflow(fresh.host);
  assert.ok(fresh.inputs.audit.includes("execute every acceptance-named test yourself"),
    "no prior evidence: audit executes as today");
});

// --- run-folder transport variants (followup.1 cycle 2): the
// --- existing handoff folder passes canonical and
// --- prose-shaped lines; a folder missing a file still fails ---
test("run-folder transport variants (followup.1 cycle 2): the existing handoff folder passes canonical and prose-shaped lines; a folder missing a file still fails", async () => {
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
    assert.ok(row && row.verdict === "pass" && row.evidence.quote.includes(HANDOFF),
      "canonical line passes the existing handoff folder");
    assert.ok(inputs.validations.includes("for d in"),
      "validations transport carries the run-folder one-liner");
    assert.ok(inputs.validations.includes("never reformat its lines"),
      "validations transport forbids prose reformatting");
  }
  for (const line of [
    HANDOFF + ": tape.log present, notes.md present",
    HANDOFF + " tape: yes, notes: yes",
    HANDOFF + "/ contains tape.log and notes.md",
  ]) {
    const { result } = await runFolderCase([line]);
    assert.ok(rowNamed(result, "adherence: run folder present").verdict === "pass",
      "prose-shaped line passes: " + line);
  }
  {
    const { result } = await runFolderCase(HANDOFF + " tape=yes notes=yes\n20260101T000000Z-verify-muse-code-test-model-c1 tape=yes notes=no");
    assert.ok(rowNamed(result, "adherence: run folder present").verdict === "pass",
      "newline string transport passes");
  }
  for (const bad of [[], [HANDOFF + " tape=yes notes=no"], [HANDOFF + " tape=no notes=yes"],
                     [HANDOFF + ": tape.log present, notes.md missing"]]) {
    const { result } = await runFolderCase(bad);
    assert.ok(rowNamed(result, "adherence: run folder present").verdict === "fail",
      "folder missing a file still fails: " + JSON.stringify(bad));
    assert.ok(result.outcome === "needs_fix", "missing-file folder still gates");
  }
});

// --- workflow-birth: the read carries the desk ---
test("workflow-birth: the read carries the desk", async () => {
  const { host, inputs } = mockHost({
    reads: [handedOff, approved],
    auditRows: [passRow("acceptance: a"), passRow("adherence: tape present")],
    extraArgs: { desk: ".bp3/worktrees/toy-desk" },
  });
  const result = await workflow(host);
  assert.ok(result.outcome === "approved", "desk grade approves, got " + result.outcome);
  assert.ok(inputs.reads.length > 0, "reads captured, got " + inputs.reads.length);
  for (const read of inputs.reads) {
    assert.ok(read.includes("quest worktree `.bp3/worktrees/toy-desk`"),
      "read prompt names the desk worktree");
    assert.ok(!read.includes("named below"), "read prompt never points below for the desk");
  }
});
