// Mock-host test for skills/bp3g/workflows/bp3g-node.js
// (mvp.3): one run owns one node's FSM loop and returns
// exactly one terminal outcome (landed, blocked, deleted).
import workflow from "../skills/bp3g/workflows/bp3g-node.js";

const TS = "20260101T000000Z";
let failures = 0;
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); failures++; }
}

function mockHost({ reads, gradeReason, edgeResults, extraArgs }) {
  let readIdx = 0;
  const labels = [];
  const inputs = { reads: [] };
  const host = {
    args: Object.assign({ quest: "toy", node: "fx", ts: TS, harness: "muse-code", model: "test-model" }, extraArgs || {}),
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
      if (label.startsWith("apply")) {
        labels.push("apply");
        (inputs.apply = inputs.apply || []).push(input);
        return JSON.stringify({ ok: true, state: "approved" });
      }
      if (input.includes(" block --reason")) {
        labels.push("block");
        (inputs.block = inputs.block || []).push(input);
        return JSON.stringify({ ok: true, state: "blocked" });
      }
      if (label.startsWith("read ") || input.startsWith("Run exactly")) {
        inputs.reads.push(input);
        return JSON.stringify(reads[Math.min(readIdx++, reads.length - 1)]);
      }
      const edge = label.split(" ")[0];
      labels.push(edge);
      (inputs[edge] = inputs[edge] || []).push(input);
      const queued = edgeResults && edgeResults[edge];
      if (queued && queued.length > 0) {
        const next = queued.shift();
        return typeof next === "string" ? next : JSON.stringify(next);
      }
      const reply = { ok: true, run_id: "r-" + edge, commit: "abc1234", verdict: { ok: true } };
      if (edge === "grade" && gradeReason) {
        reply.verdict = "needs_fix";
        reply.fix = gradeReason;
        reply.reason = gradeReason;
      }
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
  const reads = [st("todo"), st("handed_off"), st("approved"), st("landed")];
  const { host, labels, inputs } = mockHost({ reads });
  const result = await workflow(host);
  assert(result.outcome === "landed" && result.node === "fx", "happy outcome landed, got " + result.outcome);
  assert(labels.filter((l) => l === "apply").length === 1, "looper casts once, got " + labels.join(","));
  assert(inputs.grade[0].includes("do not call any `bp3 q u`"), "grade child is pure");
  assert(inputs.verify[0].includes("do not call any `bp3 q u`"), "verify child is pure");
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
  const reads = [st("todo"), st("handed_off"), st("todo", 2), st("handed_off", 2), st("approved", 2), st("landed", 2)];
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

// --- typed failure fails fast: one block, verbatim reason, exit (mvp.5) ---
{
  const blockedRead = { state: "blocked", cycle: 1, commit: "abc1234", legal_edges: ["resume", "delete"], blocked: { reason: "choose storage shape", checkpoint: null, since: "2026-01-01T00:00:00Z" } };
  const reads = [st("todo"), blockedRead];
  const failure = { ok: false, run_id: "r-handoff", error: { code: "E_DECISION", facts: {}, guidance: "choose storage shape" }, reason: "choose storage shape" };
  const { host, labels, inputs } = mockHost({ reads, edgeResults: { handoff: [failure] } });
  const result = await workflow(host);
  assert(result.outcome === "blocked", "typed failure blocks, got " + result.outcome);
  assert(result.reason === "choose storage shape", "bubble reason verbatim, got " + result.reason);
  assert(result.last_edge === "handoff", "bubble last edge, got " + result.last_edge);
  assert(result.quest === "toy" && result.inbox_key === "toy/fx", "bubble quest + inbox key");
  assert(labels.filter((l) => l === "handoff").length === 1, "failed edge never retried, got " + labels.join(","));
  assert(labels.filter((l) => l === "block").length === 1, "exactly one block call, got " + labels.join(","));
  assert(inputs.block[0].includes("choose storage shape"), "block reason rides verbatim");
}

// --- silent death is orphaned: one fresh link, one replacement, no block ---
{
  const reads = [st("todo"), st("todo"), st("handed_off"), st("approved"), st("landed")];
  const { host, labels } = mockHost({ reads, edgeResults: { handoff: ["worker died without a word"] } });
  const result = await workflow(host);
  assert(result.outcome === "landed", "orphan replacement lands, got " + result.outcome);
  assert(labels.filter((l) => l === "handoff").length === 2, "one replacement author, got " + labels.join(","));
  assert(labels.filter((l) => l === "block").length === 0, "orphan never blocks, got " + labels.join(","));
  assert(result.refusals.some((r) => r.includes("orphaned")), "orphan named in refusals");
}

// --- typed grade failure blocks before any verify spawns ---
{
  const blockedRead = { state: "blocked", cycle: 1, commit: "abc1234", legal_edges: ["resume", "delete"], blocked: { reason: "pick a schema", checkpoint: null, since: "2026-01-01T00:00:00Z" } };
  const reads = [st("handed_off"), blockedRead];
  const failure = { ok: false, run_id: "r-grade", reason: "pick a schema" };
  const { host, labels } = mockHost({ reads, edgeResults: { grade: [failure] } });
  const result = await workflow(host);
  assert(result.outcome === "blocked" && result.last_edge === "grade", "grade failure blocks, got " + result.outcome);
  assert(labels.filter((l) => l === "verify").length === 0, "no verify after failed grade, got " + labels.join(","));
  assert(labels.filter((l) => l === "block").length === 1, "one block after grade failure");
}

// --- cycle cap: bp3 already blocked; bubble carries its reason, no re-block ---
{
  const blockedRead = { state: "blocked", cycle: 1, commit: "abc1234", legal_edges: ["resume", "delete"], blocked: { reason: "fix the parser", checkpoint: null, since: "2026-01-01T00:00:00Z" } };
  const reads = [st("handed_off"), blockedRead];
  const { host, labels } = mockHost({ reads, gradeReason: "fix the parser" });
  const result = await workflow(host);
  assert(result.outcome === "blocked", "cap outcome blocked, got " + result.outcome);
  assert(result.reason === "fix the parser", "cap bubble reason, got " + result.reason);
  assert(labels.filter((l) => l === "block").length === 0, "cap block is bp3's, not re-called, got " + labels.join(","));
}

// --- workflow-birth: the read carries the desk; context rides ---
{
  const reads = [st("todo"), st("handed_off"), st("approved"), st("landed")];
  const { host, inputs } = mockHost({
    reads,
    extraArgs: { desk: ".bp3/worktrees/toy-desk", context: "rename the widget verb, keep tests green" },
  });
  const result = await workflow(host);
  assert(result.outcome === "landed", "desk+context run lands, got " + result.outcome);
  assert(inputs.reads.length > 0, "reads captured, got " + inputs.reads.length);
  for (const read of inputs.reads) {
    assert(read.includes("quest worktree `.bp3/worktrees/toy-desk`"),
      "read prompt names the desk worktree");
    assert(!read.includes("named below"), "read prompt never points below for the desk");
  }
  assert(inputs.handoff[0].includes("rename the widget verb, keep tests green"),
    "conductor context rides the first author brief verbatim");
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
console.log("bp3g-node tests: ok");
