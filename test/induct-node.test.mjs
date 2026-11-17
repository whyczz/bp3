// Mock-host test for skills/traverse/workflows/induct-node.js
// (mvp.3): one run owns one node's FSM loop and returns
// exactly one terminal outcome (landed, blocked, deleted).
import workflow from "../skills/traverse/workflows/induct-node.js";

const TS = "20260101T000000Z";
let failures = 0;
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); failures++; }
}

function mockHost({ reads, gradeReason }) {
  let readIdx = 0;
  const labels = [];
  const inputs = {};
  const host = {
    args: { quest: "toy", exp: "fx", ts: TS, harness: "muse-code", model: "test-model" },
    async agent({ label, input }) {
      if (input.includes("harness link mint")) {
        labels.push("mint");
        const e = input.match(/--edge (\S+)/);
        const edge = e ? e[1] : "node";
        const runId = TS + "-" + edge + "-muse-code-test-model-c1";
        return JSON.stringify({ ok: true, token: "bp3link_test-" + edge, run_id: runId });
      }
      if (input.includes("harness find-tape")) {
        labels.push("resolve");
        const m = input.match(/--run-id (\S+)/);
        return JSON.stringify({ ok: true, run_id: m ? m[1] : "", tape_path: "/tmp/tape.jsonl" });
      }
      if (input.includes("harness bind-tape")) {
        labels.push("bind");
        return JSON.stringify({ ok: true });
      }
      if (input.startsWith("Run exactly")) {
        return JSON.stringify(reads[Math.min(readIdx++, reads.length - 1)]);
      }
      const edge = label.split(" ")[0];
      labels.push(edge);
      (inputs[edge] = inputs[edge] || []).push(input);
      const reply = { ok: true, run_id: "r-" + edge, commit: "abc1234", verdict: { ok: true } };
      if (edge === "grade" && gradeReason) reply.reason = gradeReason;
      return JSON.stringify(reply);
    },
    async parallel(calls) {
      const out = [];
      for (const c of calls) out.push(await host.agent(c));
      return out;
    },
  };
  return { host, labels, inputs };
}

const st = (state, cycle) => ({ state, cycle: cycle || 1, commit: "abc1234", legal_edges: [] });

// --- happy path: todo -> handed_off -> approved -> landed, one outcome ---
{
  const reads = [st("todo"), st("handed_off"), st("handed_off"), st("approved"), st("landed")];
  const { host, labels, inputs } = mockHost({ reads });
  const result = await workflow(host);
  assert(result.outcome === "landed" && result.node === "fx", "happy outcome landed, got " + result.outcome);
  assert(result.commit === "abc1234", "happy commit, got " + result.commit);
  assert(labels.filter((l) => l === "handoff").length === 1, "one author, got " + labels.join(","));
  assert(labels.filter((l) => l === "grade").length === 1, "one grade, got " + labels.join(","));
  assert(labels.filter((l) => l === "verify").length === 1, "one verify, got " + labels.join(","));
  assert(labels.filter((l) => l === "land").length === 1, "one land, got " + labels.join(","));
  assert(inputs.grade[0].includes("abc1234"), "grade judges the bound commit");
  assert(inputs.handoff[0].includes("link claim bp3link_test-handoff"), "author claims first");
  assert(inputs.land[0].includes("u fx land"), "land child calls the land edge");
  assert(result.run_ids.length >= 4, "run_ids collected, got " + result.run_ids.join(","));
}

// --- needs_fix rides the loop: fix carried verbatim to the next author ---
{
  const reads = [st("todo"), st("handed_off"), st("todo", 2), st("todo", 2), st("handed_off", 2), st("handed_off", 2), st("approved", 2), st("landed", 2)];
  const { host, inputs } = mockHost({ reads, gradeReason: "fix the parser" });
  const result = await workflow(host);
  assert(result.outcome === "landed", "cycle outcome landed, got " + result.outcome);
  assert(inputs.handoff.length === 2, "two authors across cycles, got " + inputs.handoff.length);
  assert(inputs.handoff[1].includes("fix the parser"), "named fix rides verbatim");
}

// --- terminal states return at once, no edge worker spawns ---
for (const state of ["blocked", "deleted", "landed"]) {
  const { host, labels } = mockHost({ reads: [st(state)] });
  const result = await workflow(host);
  assert(result.outcome === state, state + " outcome, got " + result.outcome);
  assert(labels.length === 0, "no spawns for " + state + ", got " + labels.join(","));
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
console.log("induct-node tests: ok");
