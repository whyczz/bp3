// Conduction smoke drive for /bp3g (skills/bp3g/SKILL.md).
// One fixture node is driven end to end by the conductor dispatch
// table — todo -> node-loop, handed_off -> bp3g-grade,
// approved -> bp3g-land — against a shared fixture state
// machine, ending landed (reported node_fin). Each step is the
// real workflow file; only the host (agent spawns and bp3 reads)
// is mocked, so this proves conduction, not per-workflow parity.
import { readFileSync } from "node:fs";
import nodeLoop from "../skills/bp3g/workflows/node-loop.js";
import inductGrade from "../skills/bp3g/workflows/bp3g-grade.js";
import graphLand from "../skills/bp3g/workflows/bp3g-land.js";

const TS = "20260101T000000Z";
const COMMIT = "abc1234";
let failures = 0;
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); failures++; }
}

function passRow(name) {
  return {
    case: name,
    evidence: { kind: "command", ref: "test/bp3g.sh", quote: "bp3g tests: ok" },
    verdict: "pass",
  };
}

// Shared fixture: one node whose state only the stage children
// advance, exactly as bp3 g u edges would. Reads always report
// the current fixture state.
function fixtureHost() {
  let current = { state: "todo", cycle: 1, commit: null, legal_edges: ["handoff"] };
  const stages = [];
  const host = {
    args: { graph: "toy", node: "fx", ts: TS, harness: "muse-code", model: "test-model", commit: null },
    async agent({ label, input }) {
      if (label.startsWith("validations")) {
        return JSON.stringify({
          git_clean: { stdout: "", exit: 0 },
          git_show: { stdout: COMMIT + " subject\n", exit: 0 },
          run_folders: ["20260101T000000Z-handoff-muse-code-test-model-c1 tape=yes notes=yes"],
          handoff_line: '{"edge":"handoff","run_id":"r-build","commit":"' + COMMIT + '"}',
        });
      }
      // Stage children first: their briefs mention harness
      // commands (find-tape in the ladder text) without calling them.
      const stage = label.split(" ")[0];
      if (["author", "audit", "grade", "verify", "land"].includes(stage)) {
        stages.push(stage);
        if (stage === "author") {
          current = { state: "handed_off", cycle: 1, commit: COMMIT, legal_edges: ["grade", "verify"] };
          host.args.commit = COMMIT;
          return JSON.stringify({ ok: true, run_id: "r-author", commit: COMMIT, verdict: { ok: true } });
        }
        if (stage === "audit") {
          return JSON.stringify({ ok: true, run_id: "r-audit", matrix: [passRow("acceptance: fixture node")] });
        }
        if (stage === "verify") {
          current = { state: "approved", cycle: 1, commit: COMMIT, legal_edges: ["land"] };
          return JSON.stringify({ ok: true, run_id: "r-verify", commit: COMMIT, verdict: { ok: true } });
        }
        if (stage === "land") {
          current = { state: "landed", cycle: 1, commit: COMMIT, legal_edges: [] };
          return JSON.stringify({ ok: true, run_id: "r-land", commit: COMMIT, verdict: { ok: true } });
        }
        return JSON.stringify({ ok: true, run_id: "r-" + stage, commit: COMMIT, verdict: { ok: true } });
      }
      if (input.includes("harness link mint")) {
        const e = input.match(/--edge (\S+)/);
        const edge = e ? e[1] : "audit";
        return JSON.stringify({ ok: true, token: "bp3link_test-" + edge, run_id: "20260101T000000Z-" + edge + "-muse-code-test-model-c1", harness: "muse-code" });
      }
      if (input.includes("harness find-tape")) {
        const m = input.match(/--run-id (\S+)/);
        return JSON.stringify({ ok: true, run_id: m ? m[1] : "", tape_path: "/tmp/session-tape.jsonl" });
      }
      if (input.includes("harness bind-tape")) {
        return JSON.stringify({ ok: true, run_id: "bind", tape_path: "/tmp/session-tape.jsonl" });
      }
      if (input.startsWith("Run exactly")) {
        return JSON.stringify(current);
      }
      return JSON.stringify({ ok: true, run_id: "r-unknown", verdict: { ok: true } });
    },
    async parallel(calls) {
      const out = [];
      for (const c of calls) out.push(await host.agent(c));
      return out;
    },
  };
  return { host, stages, state: () => current.state };
}

// --- bp3g conducts: one fixture node, handoff -> grade -> land ---
{
  const { host, stages, state } = fixtureHost();
  const dispatched = [];
  const outcomes = [];
  // Conductor loop, bp3g Procedure steps 3/5: dispatch the
  // one step the fresh state calls for, then re-read.
  for (let step = 0; step < 6 && state() !== "landed"; step++) {
    const s = state();
    if (s === "todo") {
      dispatched.push("node-loop");
      outcomes.push((await nodeLoop(host)).outcome);
    } else if (s === "handed_off") {
      dispatched.push("bp3g-grade");
      outcomes.push((await inductGrade(host)).outcome);
    } else if (s === "approved") {
      dispatched.push("bp3g-land");
      outcomes.push((await graphLand(host)).outcome);
    } else {
      break;
    }
  }
  assert(dispatched.join(",") === "node-loop,bp3g-grade,bp3g-land",
    "bp3g dispatches handoff, grade, land in order, got " + dispatched.join(","));
  assert(outcomes.join(",") === "handed_off,approved,landed",
    "each step lands its transition, got " + outcomes.join(","));
  assert(stages.join(",") === "author,audit,grade,verify,land",
    "stage children run once each in order, got " + stages.join(","));
  assert(state() === "landed", "fixture node reaches landed (node_fin), got " + state());
  assert(host.args.commit === COMMIT, "bound commit flows from handoff into grade");
}

// --- the conductor table in the skill names these same steps ---
{
  const skill = readFileSync(new URL("../skills/bp3g/SKILL.md", import.meta.url), "utf8");
  assert(skill.includes("`node-loop` workflow"), "bp3g names node-loop for todo");
  assert(skill.includes("`bp3g-grade` workflow"), "bp3g names bp3g-grade for handed_off");
  assert(skill.includes("`bp3g-land` workflow"), "bp3g names bp3g-land for approved");
}

if (failures > 0) process.exit(1);
console.log("bp3g-conduct tests: ok");
