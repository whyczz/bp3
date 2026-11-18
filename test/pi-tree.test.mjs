// mvp.5 Pi proof: a real root -> node-worker -> edge-worker
// process tree. Workers are real OS processes claiming real
// bp3 links; death is checked on the process table
// (kill(pid, 0)), never inferred from node state alone.
// Cases: terminal bubble exactly once with facts only,
// whole tree dead after the bubble, unreaped grandchild
// dispositioned via parent_run_id + watch, fresh-tree
// revival after resume, root-session death revived from
// bp3 rollup + inbox by a new root process.
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const qBin = path.join(repoRoot, "_build", "default", "src", "graph", "main.exe");
let failures = 0;
function assert(cond, msg) {
  if (!cond) { console.error("FAIL: " + msg); failures++; }
}
function alive(pid) {
  try { process.kill(pid, 0); return true; } catch { return false; }
}
async function waitDead(pid, ms = 5000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (!alive(pid)) return true;
    await new Promise((r) => setTimeout(r, 50));
  }
  return !alive(pid);
}

const work = fs.mkdtempSync(path.join(os.tmpdir(), "bp3-pi-tree-"));
const repo = path.join(work, "repo");
fs.mkdirSync(path.join(repo, "bin"), { recursive: true });
fs.mkdirSync(path.join(repo, "plans"), { recursive: true });
fs.copyFileSync(path.join(repoRoot, "bin", "bp3"), path.join(repo, "bin", "bp3"));
fs.copyFileSync(qBin, path.join(repo, "g-bin"));
for (const f of fs.readdirSync(path.join(repoRoot, "plans"))) {
  if (f.endsWith(".yaml")) fs.copyFileSync(path.join(repoRoot, "plans", f), path.join(repo, "plans", f));
}
execFileSync("git", ["init", "-q", "-b", "master", repo]);
execFileSync("git", ["-C", repo, "config", "user.email", "t@t.t"]);
execFileSync("git", ["-C", repo, "config", "user.name", "t"]);
fs.writeFileSync(path.join(repo, "a.txt"), "base\n");
fs.writeFileSync(path.join(repo, ".gitignore"), ".bp3-context.json\n");
execFileSync("git", ["-C", repo, "add", "."]);
execFileSync("git", ["-C", repo, "commit", "-qm", "base"]);

const env = { ...process.env, BP3_HARNESS: "muse-code", BP3_MODEL: "test-model", BP3_G_BIN: path.join(repo, "g-bin") };
function bp3(args, extraEnv = {}) {
  const out = execFileSync(path.join(repo, "bin", "bp3"), args, { cwd: repo, encoding: "utf8", env: { ...env, ...extraEnv } });
  return JSON.parse(out.trim().split("\n").pop() ?? "{}");
}
function bp3Fail(args, extraEnv = {}) {
  try {
    execFileSync(path.join(repo, "bin", "bp3"), args, { cwd: repo, encoding: "utf8", env: { ...env, ...extraEnv } });
    return null;
  } catch (e) {
    return JSON.parse((e.stdout ?? "").trim().split("\n").pop() ?? "{}");
  }
}
const commonDir = execFileSync("git", ["-C", repo, "rev-parse", "--git-common-dir"], { encoding: "utf8" }).trim();
const runsDir = path.join(path.isAbsolute(commonDir) ? commonDir : path.join(repo, commonDir), "bp3", "runs");
function runCfg(runId) {
  return JSON.parse(fs.readFileSync(path.join(runsDir, runId + ".json"), "utf8"));
}

// --- worker scripts: real processes, claim first, then work ---
const nodeWorker = path.join(work, "node-worker.mjs");
fs.writeFileSync(nodeWorker, `
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
const [mode, graph, node, token, bubblePath, scratch] = process.argv.slice(2);
const bp3 = (args, extra = {}) => JSON.parse(execFileSync("./bin/bp3", args, { encoding: "utf8", env: { ...process.env, ...extra } }).trim().split("\\n").pop());
bp3(["harness", "link", "claim", token]);
const myCfg = JSON.parse(fs.readFileSync(process.env.BP3_RUN_CFG, "utf8"));
const myRun = myCfg.run_id;
if (mode === "orphan-parent") {
  const minted = bp3(["harness", "link", "mint", "--kind", "edge", "--graph", graph, "--node", node, "--edge", "handoff", "--harness", "pi", "--model", "test-model", "--cycle", "1", "--desk", process.cwd(), "--parent-run-id", myRun]);
  const child = spawn(process.execPath, [process.env.EDGE_WORKER, "sleep", graph, node, minted.token, scratch], { stdio: "ignore", detached: false });
  fs.writeFileSync(scratch, JSON.stringify({ grandchild_pid: child.pid, grandchild_run: minted.run_id, node_run: myRun }));
  process.exit(0); // die without reaping: grandchild is unreaped
}
const minted = bp3(["harness", "link", "mint", "--kind", "edge", "--graph", graph, "--node", node, "--edge", "handoff", "--harness", "pi", "--model", "test-model", "--cycle", "1", "--desk", process.cwd(), "--parent-run-id", myRun]);
const resultFile = scratch + ".edge.json";
const child = spawn(process.execPath, [process.env.EDGE_WORKER, mode, graph, node, minted.token, resultFile], { stdio: "inherit" });
fs.writeFileSync(scratch + ".edge.pid", String(child.pid));
const code = await new Promise((r) => child.once("exit", r));
let edgeResult = null;
try { edgeResult = JSON.parse(fs.readFileSync(resultFile, "utf8")); } catch {}
const chain = [myRun, minted.run_id];
if (edgeResult && edgeResult.ok === false) {
  bp3(["g", graph, "u", node, "block", "--reason", edgeResult.reason]);
  const bubble = { graph, node, state: "blocked", reason: edgeResult.reason, last_edge: "handoff", run_chain: chain, desk: process.cwd(), inbox_key: graph + "/" + node };
  fs.appendFileSync(bubblePath, JSON.stringify(bubble) + "\\n");
  process.exit(0);
}
const after = bp3(["g", graph, "r", node]);
const bubble = { graph, node, state: after.state, reason: null, last_edge: "handoff", run_chain: chain, desk: process.cwd(), inbox_key: graph + "/" + node };
fs.appendFileSync(bubblePath, JSON.stringify(bubble) + "\\n");
process.exit(0);
`);
const edgeWorker = path.join(work, "edge-worker.mjs");
fs.writeFileSync(edgeWorker, `
import { execFileSync } from "node:child_process";
import fs from "node:fs";
const [mode, graph, node, token, resultFile] = process.argv.slice(2);
const bp3 = (args, extra = {}) => JSON.parse(execFileSync("./bin/bp3", args, { encoding: "utf8", env: { ...process.env, ...extra } }).trim().split("\\n").pop());
bp3(["harness", "link", "claim", token]);
if (mode === "sleep") {
  // No parked workers: an edge worker whose parent died exits.
  const iv = setInterval(() => { if (process.ppid === 1) { clearInterval(iv); process.exit(0); } }, 100);
  setTimeout(() => {}, 30000);
}
else if (mode === "block-fail") {
  fs.writeFileSync(resultFile, JSON.stringify({ ok: false, kind: "typed_failure", code: "E_DECISION", reason: "choose storage shape" }));
} else if (mode === "handoff") {
  fs.writeFileSync("a.txt", "fresh tree work\\n");
  execFileSync("git", ["add", "a.txt"]);
  execFileSync("git", ["commit", "-qm", "fresh tree work"]);
  const commit = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  bp3(["g", graph, "u", node, "handoff", "--commit", commit, "--reason", "fresh tree work"]);
  fs.writeFileSync(resultFile, JSON.stringify({ ok: true }));
}
`);

function spawnNode(mode, graph, node, bubblePath, scratch) {
  const minted = bp3(["harness", "link", "mint", "--kind", "node", "--graph", graph, "--node", node,
    "--harness", "pi", "--model", "test-model", "--cycle", "1", "--desk", repo]);
  const cfgPath = path.join(runsDir, minted.run_id + ".json");
  const child = spawn(process.execPath, [nodeWorker, mode, graph, node, minted.token, bubblePath, scratch], {
    cwd: repo,
    env: { ...env, BP3_RUN_ID: minted.run_id, BP3_RUN_CFG: cfgPath, EDGE_WORKER: edgeWorker },
    stdio: "inherit",
  });
  return { child, runId: minted.run_id, pid: child.pid };
}
const exitOf = (child) => new Promise((r) => child.once("exit", r));

try {
  bp3(["g", "c", "demo"]);
  bp3(["g", "demo", "c", "pinode"]);

  // --- bubble exactly once, facts only; whole tree dies ---
  const bubblePath = path.join(work, "bubbles.jsonl");
  const scratch = path.join(work, "s1");
  const first = spawnNode("block-fail", "demo", "pinode", bubblePath, scratch);
  assert((await exitOf(first.child)) === 0, "node worker exits 0 on block");
  const bubbles = fs.readFileSync(bubblePath, "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert(bubbles.length === 1, "exactly one terminal bubble, got " + bubbles.length);
  const b = bubbles[0];
  assert(b.graph === "demo" && b.node === "pinode" && b.state === "blocked" && b.reason === "choose storage shape"
    && b.last_edge === "handoff" && b.inbox_key === "demo/pinode" && typeof b.desk === "string"
    && Array.isArray(b.run_chain) && b.run_chain.length === 2 && !("pid" in b), "bubble carries facts only: " + JSON.stringify(b));
  const edgeCfg = runCfg(b.run_chain[1]);
  assert(edgeCfg.creator.run_id === b.run_chain[0], "edge run hangs off node run via parent_run_id");
  assert(await waitDead(first.pid), "node worker pid dead after bubble");
  const edgePid = Number(fs.readFileSync(scratch + ".edge.pid", "utf8"));
  assert(await waitDead(edgePid), "edge worker pid dead after bubble (process table)");
  let read = bp3(["g", "demo", "r", "pinode"]);
  assert(read.state === "blocked" && read.blocked.reason === "choose storage shape", "node rests blocked");
  let rollup = bp3(["g", "r", "demo"]);
  assert(rollup.inbox.filter((i) => i.node === "pinode").length === 1, "exactly one inbox entry");

  // --- revival is a fresh tree: new claim/run chain, no reuse ---
  const resumed = bp3(["g", "demo", "u", "pinode", "resume", "--reason", "use localStorage"], { BP3_DECIDER: "human" });
  assert(resumed.ok === true && resumed.state === "todo", "resume revives to todo");
  const second = spawnNode("handoff", "demo", "pinode", bubblePath, path.join(work, "s2"));
  assert((await exitOf(second.child)) === 0, "revived node worker exits 0");
  assert(second.runId !== first.runId && second.pid !== first.pid, "fresh run-id and pid, no reuse");
  const secondCfg = runCfg(second.runId);
  assert(secondCfg.claim.session_id !== runCfg(first.runId).claim.session_id || secondCfg.claim.pid !== runCfg(first.runId).claim.pid, "fresh claim identity");
  read = bp3(["g", "demo", "r", "pinode"]);
  assert(read.state === "handed_off", "fresh tree drives node to handed_off, got " + read.state);

  // --- unreaped grandchild: root follows parent_run_id, watch dispositions ---
  bp3(["g", "demo", "c", "orphanode"]);
  const orphanScratch = path.join(work, "orphan.json");
  const parent = spawnNode("orphan-parent", "demo", "orphanode", bubblePath, orphanScratch);
  assert((await exitOf(parent.child)) === 0, "orphan-parent node worker dies first");
  const orphan = JSON.parse(fs.readFileSync(orphanScratch, "utf8"));
  assert(runCfg(orphan.grandchild_run).creator.run_id === orphan.node_run, "grandchild chain via parent_run_id");
  assert(alive(orphan.grandchild_pid), "grandchild still live before disposition (genuinely unreaped)");
  // The grandchild claims its link after node starts; only a claimed Run has a record to watch.
  const claimEnd = Date.now() + 5000;
  while (!runCfg(orphan.grandchild_run).claim && Date.now() < claimEnd) await new Promise((r) => setTimeout(r, 50));
  assert(runCfg(orphan.grandchild_run).claim, "grandchild claimed its link before disposition");
  const tapePath = path.join(work, "grandchild.jsonl");
  fs.writeFileSync(tapePath, JSON.stringify({ type: "message", id: "g1", message: { role: "user", content: "work" } }) + "\n");
  bp3(["harness", "bind-tape", "--run-id", orphan.grandchild_run, "--tape-path", tapePath]);
  const verdict = bp3Fail(["harness", "watch", "--run-id", orphan.grandchild_run, "--silence-seconds", "1", "--timeout-seconds", "20", "--grace-seconds", "1"]) ?? {};
  assert(verdict.lifecycle === "orphaned", "watch dispositions grandchild orphaned: " + JSON.stringify(verdict));
  assert(await waitDead(orphan.grandchild_pid), "grandchild dead after disposition; tree dead");

  // --- root dies: a new root process revives from rollup + inbox alone ---
  bp3(["g", "demo", "c", "rootnode"]);
  const rootBubble = path.join(work, "root-bubbles.jsonl");
  const dying = spawnNode("block-fail", "demo", "rootnode", rootBubble, path.join(work, "s3"));
  await exitOf(dying.child);
  const newRoot = path.join(work, "new-root.mjs");
  fs.writeFileSync(newRoot, `
import { execFileSync, spawn } from "node:child_process";
const bp3 = (args, extra = {}) => JSON.parse(execFileSync("./bin/bp3", args, { encoding: "utf8", env: { ...process.env, ...extra } }).trim().split("\\n").pop());
const rollup = bp3(["g", "r", "demo"]);
const hit = rollup.inbox.find((i) => i.node === "rootnode");
if (!hit || hit.reason !== "choose storage shape") process.exit(2);
bp3(["g", "demo", "u", "rootnode", "resume", "--reason", "use localStorage"], { BP3_DECIDER: "human" });
const minted = bp3(["harness", "link", "mint", "--kind", "node", "--graph", "demo", "--node", "rootnode", "--harness", "pi", "--model", "test-model", "--cycle", "1", "--desk", process.cwd()]);
console.log(JSON.stringify({ run_id: minted.run_id, token: minted.token }));
`);
  const fresh = JSON.parse(execFileSync(process.execPath, [newRoot], { cwd: repo, encoding: "utf8", env }).trim().split("\n").pop());
  assert(fresh.run_id !== dying.runId, "new root mints a fresh node run");
  read = bp3(["g", "demo", "r", "rootnode"]);
  assert(read.state === "todo", "rootnode revived to todo by new root, got " + read.state);
} finally {
  try { fs.rmSync(work, { recursive: true, force: true }); } catch {}
}
if (failures > 0) process.exit(1);
console.log("pi-tree tests: ok");
