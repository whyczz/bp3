// Mock-host test for skills/traverse/workflows/quest-land.js.
// The land step owns one transition: an approved exp spawns
// exactly one land child; any other state refuses with zero
// children and untouched state.
import workflow from "../skills/traverse/workflows/quest-land.js";

const TS = "20260101T000000Z";
let failures = 0;
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); failures++; }
}

function mockHost({ reads, initFails }) {
  let readIdx = 0;
  const labels = [];
  const inputs = {};
  const inits = [];
  const host = {
    args: { quest: "toy", exp: "fx", ts: TS, harness: "muse-code", model: "test-model" },
    async agent({ label, input }) {
      if (input.includes("harness link mint")) {
        labels.push("init");
        inputs.init = input;
        const e = input.match(/--edge (\S+)/);
        const edge = e ? e[1] : "node";
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
  return { host, labels, inputs, inits };
}

const approved = { state: "approved", cycle: 1, commit: "abc1234", legal_edges: ["land"] };
const landed = { state: "landed", cycle: 1, commit: "abc1234", legal_edges: [] };

// --- approved: writer first, then exactly one land child ---
{
  const { host, labels, inputs, inits } = mockHost({ reads: [approved, landed] });
  const result = await workflow(host);
  assert(result.outcome === "landed", "approved exp lands, got " + result.outcome);
  assert(labels.join(",") === "init,land", "writer precedes the land child, got " + labels.join(","));
  assert(inits.join(",") === TS + "-land-muse-code-test-model-c1",
    "mint names the land run-id, got " + inits.join(","));
  const input = inputs.land;
  assert(input.includes("link claim bp3link_test-land"), "land brief carries its claim token");
  assert(input.includes("BP3_RUN_ID=<that run_id>"), "land is told to stamp the claimed run-id");
  assert(input.includes("runs/" + TS + "-land-muse-code-test-model-c1"),
    "land run folder matches the minted run-id");
  assert(!input.includes("Prefix your FIRST"),
    "land brief carries no first-command prefix instruction");
  assert(input.includes("arrives via the"),
    "land is told the run-id arrives via the claim");
  assert(input.includes("u fx land --reason"), "land child calls the land edge");
  assert(result.run_ids.join(",") === TS + "-land-muse-code-test-model-c1,r-land", "run_ids collect mint and land child, got " + result.run_ids.join(","));
}

// --- any other state refuses with zero children ---
for (const state of ["todo", "handed_off", "landed", "blocked"]) {
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
  assert(labels.join(",") === "init,land", "land ran exactly once, got " + labels.join(","));
}

// --- writer refused: the land child never starts (mvp.1) ---
{
  const { host, labels } = mockHost({ reads: [approved, approved], initFails: true });
  const result = await workflow(host);
  assert(result.outcome === "refused", "writer refusal refuses the step, got " + result.outcome);
  assert(labels.join(",") === "init", "no land child spawns after a refused mint, got " + labels.join(","));
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
