// Mock-host test for skills/induct/workflows/induct-exp.js.
// Asserts the per-stage witnessed binding: every stage child's
// commands carry BP3_RUN_ID=<ts>-<edge>-<harness>-<model>-c<cycle>
// matching its run folder, so a PreToolUse hook can bind
// session -> run from the command text alone.
import workflow from "../skills/induct/workflows/induct-exp.js";

const TS = "20260101T000000Z";
const reads = [
  { state: "todo", cycle: 1, commit: null, legal_edges: ["submit"] },
  { state: "submitted", cycle: 1, commit: "abc1234", legal_edges: ["review", "check"] },
  { state: "approved", cycle: 1, commit: "abc1234", legal_edges: ["land"] },
  { state: "landed", cycle: 1, commit: "abc1234", legal_edges: [] },
];
let readIdx = 0;
const stageInputs = {};

const host = {
  args: { quest: "toy", exp: "fx", ts: TS, harness: "muse-code", model: "test-model" },
  async agent({ label, input }) {
    if (input.startsWith("Run exactly")) {
      return JSON.stringify(reads[Math.min(readIdx++, reads.length - 1)]);
    }
    const edge = label.startsWith("author") ? "submit" : label.split(" ")[0];
    stageInputs[edge] = input;
    return JSON.stringify({ ok: true, run_id: "r-" + edge, commit: "abc1234", verdict: { ok: true } });
  },
  async parallel(calls) {
    const out = [];
    for (const c of calls) out.push(await host.agent(c));
    return out;
  },
};

const result = await workflow(host);
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); process.exit(1); }
}
assert(result.outcome === "landed", "outcome landed, got " + result.outcome);
for (const edge of ["submit", "review", "check", "land"]) {
  const input = stageInputs[edge];
  assert(input, edge + " child was spawned");
  const want = "BP3_RUN_ID=" + TS + "-" + edge + "-muse-code-test-model-c1";
  assert(input.includes(want), edge + " command carries " + want);
  assert(input.includes("BP3_QUEST=toy") && input.includes("BP3_EXP=fx"),
    edge + " prefix carries quest/exp");
}
assert(stageInputs.submit.includes("runs/" + TS + "-submit-muse-code-test-model-c1"),
  "submit run folder matches BP3_RUN_ID");
assert(stageInputs.submit.includes("Prefix your FIRST shell command"),
  "author is told the first command binds the session");
console.log("induct-exp tests: ok");
