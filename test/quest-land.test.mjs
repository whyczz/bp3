// Mock-host test for skills/induct/workflows/quest-land.js.
// The land step owns one transition: an approved exp spawns
// exactly one land child; any other state refuses with zero
// children and untouched state.
import workflow from "../skills/induct/workflows/quest-land.js";

const TS = "20260101T000000Z";
let failures = 0;
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); failures++; }
}

function mockHost({ reads }) {
  let readIdx = 0;
  const labels = [];
  const inputs = {};
  const host = {
    args: { quest: "toy", exp: "fx", ts: TS, harness: "muse-code", model: "test-model" },
    async agent({ label, input }) {
      if (input.startsWith("Run exactly")) {
        return JSON.stringify(reads[Math.min(readIdx++, reads.length - 1)]);
      }
      const edge = label.split(" ")[0];
      labels.push(edge);
      inputs[edge] = input;
      return JSON.stringify({ ok: true, run_id: "r-" + edge, commit: "abc1234", verdict: { ok: true } });
    },
    async parallel(calls) {
      const out = [];
      for (const c of calls) out.push(await host.agent(c));
      return out;
    },
  };
  return { host, labels, inputs };
}

const approved = { state: "approved", cycle: 1, commit: "abc1234", legal_edges: ["land"] };
const landed = { state: "landed", cycle: 1, commit: "abc1234", legal_edges: [] };

// --- approved: exactly one land child; outcome is landed ---
{
  const { host, labels, inputs } = mockHost({ reads: [approved, landed] });
  const result = await workflow(host);
  assert(result.outcome === "landed", "approved exp lands, got " + result.outcome);
  assert(labels.join(",") === "land", "only the land child spawns, got " + labels.join(","));
  const input = inputs.land;
  const want = "BP3_RUN_ID=" + TS + "-land-muse-code-test-model-c1";
  assert(input.includes(want), "land command carries " + want);
  assert(input.includes("runs/" + TS + "-land-muse-code-test-model-c1"),
    "land run folder matches BP3_RUN_ID");
  assert(input.includes("u fx land --reason"), "land child calls the land edge");
  assert(result.run_ids.join(",") === "r-land", "run_ids collect the land child");
}

// --- any other state refuses with zero children ---
for (const state of ["todo", "submitted", "landed", "blocked"]) {
  const s = { state: state, cycle: 1, commit: "abc1234", legal_edges: [] };
  const { host, labels } = mockHost({ reads: [s] });
  const result = await workflow(host);
  assert(result.outcome === "refused", state + " is refused, got " + result.outcome);
  assert(labels.length === 0, "no land child spawns for " + state);
}

// --- land makes no progress: refused, exactly one child ---
{
  const { host, labels } = mockHost({ reads: [approved, approved] });
  const result = await workflow(host);
  assert(result.outcome === "refused", "no-progress land is refused, got " + result.outcome);
  assert(labels.join(",") === "land", "land ran exactly once, got " + labels.join(","));
}

// --- missing args refuse without spawning anything ---
{
  const host = {
    args: { quest: "toy" },
    async agent() { throw new Error("must not spawn"); },
    async parallel() { throw new Error("must not spawn"); },
  };
  const result = await workflow(host);
  assert(result.outcome === "refused", "missing args refuse");
}

if (failures > 0) process.exit(1);
console.log("quest-land tests: ok");
