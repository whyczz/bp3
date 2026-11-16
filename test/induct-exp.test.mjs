// Mock-host test for skills/induct/workflows/induct-exp.js.
// Covers the exp Acceptance table for the slimmed build-only
// step: the launcher's record-init writer precedes the author
// child on a todo exp (mvp.8; a refused write spawns nothing),
// only the author child spawns on a todo exp, the file
// carries no other stage's edge commands, a submitted exp is
// refused with zero stage children (state untouched), and the
// env-set run-id still holds for the author.
import { readFileSync } from "node:fs";
import workflow from "../skills/induct/workflows/induct-exp.js";

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
      if (input.includes("harness record-init")) {
        labels.push("init");
        inputs.init = input;
        const m = input.match(/--run-id (\S+)/);
        inits.push(m ? m[1] : "");
        if (initFails) {
          return JSON.stringify({ ok: false, error: { code: "E_EXISTS" } });
        }
        return JSON.stringify({ ok: true, run_id: m ? m[1] : "", harness: "muse-code" });
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

const todo = { state: "todo", cycle: 1, commit: null, legal_edges: ["submit"] };
const submitted = { state: "submitted", cycle: 1, commit: "abc1234", legal_edges: ["review", "check"] };

// --- todo: the writer records first, then only the author runs ---
{
  const { host, labels, inputs, inits } = mockHost({ reads: [todo, submitted] });
  const result = await workflow(host);
  assert(result.outcome === "submitted", "todo build submits, got " + result.outcome);
  assert(result.commit === "abc1234", "commit comes from the re-read, got " + result.commit);
  assert(labels.join(",") === "init,author", "writer precedes the author child, got " + labels.join(","));
  assert(inits.join(",") === TS + "-submit-muse-code-test-model-c1",
    "InitRecord names the author's run-id, got " + inits.join(","));
  assert(inputs.init.includes("harness record-init --run-id " + TS + "-submit-muse-code-test-model-c1"),
    "writer calls record-init for the author run-id");
  assert(inputs.init.includes("--harness muse-code") && inputs.init.includes("--quest toy") && inputs.init.includes("--exp fx"),
    "writer records harness, quest, and exp");
  const input = inputs.author;
  const want = "BP3_RUN_ID=" + TS + "-submit-muse-code-test-model-c1";
  assert(input.includes(want), "author command carries " + want);
  assert(input.includes("BP3_QUEST=toy") && input.includes("BP3_EXP=fx"),
    "author prefix carries quest/exp");
  assert(input.includes("runs/" + TS + "-submit-muse-code-test-model-c1"),
    "submit run folder matches BP3_RUN_ID");
  assert(!input.includes("Prefix your FIRST"),
    "author brief carries no first-command prefix instruction");
  assert(input.includes("arrive via environment"),
    "author is told the run-id arrives via environment");
  assert(input.includes("u fx submit --commit"), "author calls the submit edge");
  assert(result.run_ids.join(",") === "r-author", "run_ids collect the author, got " + result.run_ids.join(","));
}

// --- submitted: refuses cleanly, no stage child, state untouched ---
{
  const { host, labels } = mockHost({ reads: [submitted] });
  const result = await workflow(host);
  assert(result.outcome === "refused", "submitted exp is refused, got " + result.outcome);
  assert(labels.length === 0, "no stage child spawns for submitted");
  assert(result.refusals.some((r) => r.includes("submitted")), "refusal names the state");
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
  assert(labels.join(",") === "init,author", "author ran exactly once, got " + labels.join(","));
}

// --- writer refused: the child never starts ---
{
  const { host, labels } = mockHost({ reads: [todo, todo], initFails: true });
  const result = await workflow(host);
  assert(result.outcome === "refused", "writer refusal refuses the step, got " + result.outcome);
  assert(labels.join(",") === "init", "no author spawns after a refused InitRecord, got " + labels.join(","));
  assert(result.refusals.some((r) => r.includes("record-init")), "refusal names record-init");
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

// --- stage set is finite: no other stage's prompts in the file ---
{
  const src = readFileSync(new URL("../skills/induct/workflows/induct-exp.js", import.meta.url), "utf8");
  assert(!src.includes("host.parallel"), "no parallel stage fan-out in the file");
  assert(!src.includes("review --verdict"), "no review prompt in the file");
  assert(!src.includes("check --verdict"), "no check prompt in the file");
  assert(!src.includes(" land --reason"), "no land prompt in the file");
  assert(!src.includes("for (let stage"), "no stage loop in the file");
}

if (failures > 0) process.exit(1);
console.log("induct-exp tests: ok");
