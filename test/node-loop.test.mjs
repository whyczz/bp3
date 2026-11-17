// Mock-host test for skills/bp3g/workflows/node-loop.js.
// Covers the node Acceptance table for the slimmed build-only
// step: the launcher's link mint precedes the author
// child on a todo node (mvp.1; a refused mint spawns nothing),
// only the author child spawns on a todo node, the launcher's
// bind step follows the author (followup.3: find-tape resolves
// the session tape, bind-tape binds it; a refused resolution
// binds nothing), the file carries no other stage's edge
// commands, a handed_off node is refused with zero stage
// children (state untouched), and the env-set run-id still
// holds for the author.
import { readFileSync } from "node:fs";
import workflow from "../skills/bp3g/workflows/node-loop.js";

const TS = "20260101T000000Z";
let failures = 0;
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); failures++; }
}

function mockHost({ reads, initFails, bindFails, extraArgs }) {
  let readIdx = 0;
  const labels = [];
  const inputs = { reads: [] };
  const inits = [];
  const binds = [];
  const host = {
    args: Object.assign({ graph: "toy", node: "fx", ts: TS, harness: "muse-code", model: "test-model" }, extraArgs || {}),
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
      if (input.includes("harness find-tape")) {
        labels.push("resolve");
        inputs.resolve = input;
        if (bindFails) {
          return JSON.stringify({ ok: false, error: { code: "E_AMBIGUOUS" } });
        }
        const m = input.match(/--run-id (\S+)/);
        return JSON.stringify({ ok: true, run_id: m ? m[1] : "", tape_path: "/tmp/session-tape.jsonl", wal: "/tmp/session-tape.jsonl" });
      }
      if (input.includes("harness bind-tape")) {
        labels.push("bind");
        inputs.bind = input;
        const m = input.match(/--tape-path ([^\s`]+)/);
        binds.push(m ? m[1] : "");
        const r = input.match(/--run-id (\S+)/);
        return JSON.stringify({ ok: true, run_id: r ? r[1] : "", tape_path: m ? m[1] : "" });
      }
      if (label.startsWith("read ") || input.startsWith("Run exactly")) {
        inputs.reads.push(input);
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
  return { host, labels, inputs, inits, binds };
}

const todo = { state: "todo", cycle: 1, commit: null, legal_edges: ["handoff"] };
const handedOff = { state: "handed_off", cycle: 1, commit: "abc1234", legal_edges: ["grade", "verify"] };

// --- todo: the writer records first, the author runs, the binder follows ---
{
  const { host, labels, inputs, inits, binds } = mockHost({ reads: [todo, handedOff] });
  const result = await workflow(host);
  assert(result.outcome === "handed_off", "todo build hands off, got " + result.outcome);
  assert(result.commit === "abc1234", "commit comes from the re-read, got " + result.commit);
  assert(labels.join(",") === "init,author,resolve,bind", "writer, author, then bind step, got " + labels.join(","));
  assert(inits.join(",") === TS + "-handoff-muse-code-test-model-c1",
    "mint names the author's run-id, got " + inits.join(","));
  assert(inputs.init.includes("harness link mint") && inputs.init.includes("--edge handoff"),
    "minter calls link mint for the author edge");
  assert(inputs.init.includes("--harness muse-code") && inputs.init.includes("--graph toy") && inputs.init.includes("--node fx"),
    "minter records harness, graph, and node");
  assert(!inputs.init.includes("--tape-path"),
    "writer names no tape pre-spawn; the session tape is bound after the child returns");
  assert(inputs.resolve.includes("harness find-tape --run-id " + TS + "-handoff-muse-code-test-model-c1"),
    "binder resolves the author's session tape mechanically");
  assert(inputs.bind.includes("harness bind-tape --run-id " + TS + "-handoff-muse-code-test-model-c1"),
    "binder calls bind-tape for the author run-id");
  assert(inputs.bind.includes("--tape-path /tmp/session-tape.jsonl"),
    "binder binds the resolved session tape");
  assert(binds.join(",") === "/tmp/session-tape.jsonl",
    "exactly one binding, for the resolved tape, got " + binds.join(","));
  const input = inputs.author;
  assert(input.includes("link claim bp3link_test-handoff"), "author brief carries its claim token");
  assert(input.includes("BP3_RUN_ID=<that run_id>"), "author is told to stamp the claimed run-id");
  assert(input.includes("BP3_GRAPH=toy") && input.includes("BP3_NODE=fx"),
    "author prefix carries graph/node");
  assert(input.includes("runs/" + TS + "-handoff-muse-code-test-model-c1"),
    "handoff run folder matches the minted run-id");
  assert(!input.includes("Prefix your FIRST"),
    "author brief carries no first-command prefix instruction");
  assert(input.includes("arrives via the"),
    "author is told the run-id arrives via the claim");
  assert(input.includes("u fx handoff --commit"), "author calls the handoff edge");
  assert(result.run_ids.join(",") === TS + "-handoff-muse-code-test-model-c1,r-author", "run_ids collect mint and author, got " + result.run_ids.join(","));
}

// --- handed_off: refuses cleanly, no stage child, state untouched ---
{
  const { host, labels } = mockHost({ reads: [handedOff] });
  const result = await workflow(host);
  assert(result.outcome === "refused", "handed_off node is refused, got " + result.outcome);
  assert(labels.length === 0, "no stage child spawns for handed_off");
  assert(result.refusals.some((r) => r.includes("handed_off")), "refusal names the state");
}

// --- approved and landed also refuse: another step owns them ---
for (const state of ["approved", "landed", "blocked"]) {
  const s = { state: state, cycle: 1, commit: "abc1234", legal_edges: [] };
  const { host, labels } = mockHost({ reads: [s] });
  const result = await workflow(host);
  assert(result.outcome === "refused", state + " is refused, got " + result.outcome);
  assert(labels.length === 0, "no stage child spawns for " + state);
}

// --- author makes no progress: refused, never loops ---
{
  const { host, labels } = mockHost({ reads: [todo, todo] });
  const result = await workflow(host);
  assert(result.outcome === "refused", "no-progress author is refused, got " + result.outcome);
  assert(labels.join(",") === "init,author,resolve,bind", "author ran exactly once, then the bind step, got " + labels.join(","));
}

// --- tape resolution refuses: nothing is bound, refusal is typed ---
{
  const { host, labels, binds } = mockHost({ reads: [todo, handedOff], bindFails: true });
  const result = await workflow(host);
  assert(result.outcome === "handed_off", "bind refusal does not unhand the node, got " + result.outcome);
  assert(labels.join(",") === "init,author,resolve", "no bind child after a refused resolution, got " + labels.join(","));
  assert(binds.length === 0, "a refused resolution binds nothing, got " + binds.join(","));
  assert(result.refusals.some((r) => r.includes("bind-tape")), "refusal names bind-tape");
}

// --- writer refused: the child never starts ---
{
  const { host, labels } = mockHost({ reads: [todo, todo], initFails: true });
  const result = await workflow(host);
  assert(result.outcome === "refused", "writer refusal refuses the step, got " + result.outcome);
  assert(labels.join(",") === "init", "no author spawns after a refused mint, got " + labels.join(","));
  assert(result.refusals.some((r) => r.includes("link mint")), "refusal names link mint");
}

// --- missing args refuse without spawning anything ---
{
  const host = {
    args: { graph: "toy" },
    async agent() { throw new Error("must not spawn"); },
    async parallel() { throw new Error("must not spawn"); },
  };
  const result = await workflow(host);
  assert(result.outcome === "refused", "missing args refuse");
}

// --- workflow-birth: the read carries the desk; context rides ---
{
  const { host, inputs } = mockHost({
    reads: [todo, handedOff],
    extraArgs: { desk: ".bp3/worktrees/toy-desk", context: "rename the widget verb, keep tests green" },
  });
  const result = await workflow(host);
  assert(result.outcome === "handed_off", "desk+context build hands off, got " + result.outcome);
  assert(inputs.reads.length === 2, "two reads captured, got " + inputs.reads.length);
  for (const read of inputs.reads) {
    assert(read.includes("graph worktree `.bp3/worktrees/toy-desk`"),
      "read prompt names the desk worktree");
    assert(read.includes("named above"), "read prompt points above at the desk");
    assert(!read.includes("named below"), "read prompt never points below for the desk");
  }
  assert(inputs.author.includes("conductor named this context; carry it verbatim: rename the widget verb, keep tests green"),
    "conductor context rides the author brief verbatim");
}

// --- stage set is finite: no other stage's prompts in the file ---
{
  const src = readFileSync(new URL("../skills/bp3g/workflows/node-loop.js", import.meta.url), "utf8");
  assert(!src.includes("host.parallel"), "no parallel stage fan-out in the file");
  assert(!src.includes("grade --verdict"), "no grade prompt in the file");
  assert(!src.includes("verify --verdict"), "no verify prompt in the file");
  assert(!src.includes(" land --reason"), "no land prompt in the file");
  assert(!src.includes("for (let stage"), "no stage loop in the file");
}

if (failures > 0) process.exit(1);
console.log("node-loop tests: ok");
