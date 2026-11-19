// bp3-pi unit suite (test-pyramid js.1): fake pi children and a fake
// bp3 that replays transcripts recorded from the real binary
// (test/fake-bp3/), so this file launches no real bp3.
// Run: node --test extensions/bp3-pi/test/bp3-pi.test.mjs
// Re-record: scripts/record-transcripts; drift check: --check.
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { extRoot, makeRepo, writeFakePi, writeFakePiKind, bp3 as bp3At } from "./helpers.mjs";
import { fakeBp3 } from "./helpers.mjs";

const bp3Bin = process.env.BP3_PI_TEST_BP3 ?? fakeBp3;
const bp3 = (cwd, args) => bp3At(bp3Bin, cwd, args);
const { Dispatcher, derivationsDir, runsDir, resolveRepoRoot } = await import(path.join(extRoot, "src", "dispatcher.ts"));
const { validateInput, RefusedInput } = await import(path.join(extRoot, "src", "contract.ts"));
const extension = (await import(path.join(extRoot, "index.ts"))).default;

test("extension registers exactly four tools and loads fail-open", async () => {
  const tools = [];
  extension({ registerTool: (t) => tools.push(t), on: () => {} });
  assert.deepEqual(tools.map((t) => t.name).sort(), ["await_runs", "list_runs", "release_desk", "spawn_run"]);

  const [spawn] = tools.filter((t) => t.name === "spawn_run");
  const repo = makeRepo();
  // The tool itself returns a typed refusal, never a throw,
  // when bp3 cannot be reached (here: no bin/bp3 in repo).
  const refused = await spawn.execute("c", { quest: "g", node: "e", edge: "handoff", prompt: "hi" }, null, null, { cwd: repo });
  assert.equal(refused.isError, true);
  assert.equal(JSON.parse(refused.content[0].text).error.code, "E_BP3_UNREACHABLE");
  const missing = new Dispatcher({ cwd: repo, bp3Bin: "/nonexistent/bp3", piBin: "/nonexistent/pi" });
  await assert.rejects(() => missing.spawnRun({ quest: "g", node: "e", edge: "handoff", prompt: "hi" }), (e) => e.code === "E_BP3_UNREACHABLE");
});

test("hostile inputs are refused E_REFUSED_INPUT naming the key", () => {
  const base = { quest: "g", node: "e", edge: "handoff", prompt: "hi" };
  for (const [extra, key] of [
    [{ BP3_DECIDER: "x" }, "BP3_DECIDER"],
    [{ env: { A: "1" } }, "env"],
    [{ tools: ["bash"] }, "tools"],
    [{ run_id: "20260101T000000Z-handoff-pi-m-c1" }, "run_id"],
    [{ runId: "x" }, "runId"],
  ]) {
    assert.throws(() => validateInput({ ...base, ...extra }), (e) => e instanceof RefusedInput && e.code === "E_REFUSED_INPUT" && e.key === key);
  }
  assert.equal(validateInput(base).prompt, "hi");
});

test("roles route model/thinking into the child env: override > role > conductor", async () => {
  const repo = makeRepo();
  const fakePi = writeFakePi(repo);
  const rolesDir = fs.mkdtempSync(path.join(os.tmpdir(), "bp3-pi-roles-"));
  fs.writeFileSync(path.join(rolesDir, "scout.md"), "---\nmodel: role-model\nthinking: high\ntools: read,bash\n---\nScout.\n");
  const env = { ...process.env, BP3_MODEL: "conductor-model", BP3_THINKING: "low" };
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: fakePi, env, rolesDir });

  // Role beats the conductor's env, observed in the child's
  // captured env and in the run config bp3 wrote.
  const roled = await dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", role: "scout" });
  assert.equal(roled.model, "role-model");
  assert.equal(roled.thinking, "high");
  let capture = JSON.parse(fs.readFileSync(path.join(path.dirname(roled.tape_path), "env-capture.json"), "utf8"));
  assert.equal(capture.BP3_MODEL, "role-model");
  assert.equal(capture.BP3_THINKING, "high");
  assert.ok(capture.argv.includes("--model") && capture.argv.includes("role-model"));
  assert.ok(capture.argv.includes("--tools") && capture.argv.includes("read,bash"));
  let cfg = JSON.parse(fs.readFileSync(path.join(runsDir(repo), `${roled.run_id}.json`), "utf8"));
  assert.equal(cfg.creator.model, "role-model");
  assert.equal(cfg.creator.thinking, "high");

  // A named override beats the role on both fields.
  const overridden = await dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", role: "scout", model: "override-model", thinking: "max", cycle: 2 });
  capture = JSON.parse(fs.readFileSync(path.join(path.dirname(overridden.tape_path), "env-capture.json"), "utf8"));
  assert.equal(capture.BP3_MODEL, "override-model");
  assert.equal(capture.BP3_THINKING, "max");
  cfg = JSON.parse(fs.readFileSync(path.join(runsDir(repo), `${overridden.run_id}.json`), "utf8"));
  assert.equal(cfg.creator.model, "override-model");
  assert.equal(cfg.creator.thinking, "max");

  // No role: the conductor's env is the last resort, still explicit.
  const plain = await dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", cycle: 3 });
  capture = JSON.parse(fs.readFileSync(path.join(path.dirname(plain.tape_path), "env-capture.json"), "utf8"));
  assert.equal(capture.BP3_MODEL, "conductor-model");
  assert.equal(capture.BP3_THINKING, "low");

  // The bundled role files parse to the decided cast.
  const bundled = new Dispatcher({ cwd: repo, bp3Bin, piBin: fakePi, env });
  const authored = await bundled.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", role: "author", cycle: 4 });
  assert.equal(authored.model, "openai/gpt-6.1-sol");
  assert.equal(authored.thinking, "medium");

  await assert.rejects(
    () => dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", role: "nope", cycle: 5 }),
    (e) => e.code === "E_NOT_FOUND",
  );
});

test("dispatcher never signals a pid: watch is the sole killer", () => {
  const src = fs.readFileSync(path.join(extRoot, "src", "dispatcher.ts"), "utf8");
  assert.ok(!/SIGTERM|SIGKILL|\.kill\(/.test(src), "dispatcher signals a pid");
});

test("dispatcher writes nothing itself: the run config is bp3-written", async () => {
  const repo = makeRepo();
  const fakePi = writeFakePi(repo);
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: fakePi });
  const result = await dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" });
  assert.ok(fs.existsSync(path.join(runsDir(repo), `${result.run_id}.json`)));
  const dir = derivationsDir(repo);
  const files = fs.existsSync(dir) ? fs.readdirSync(dir).sort() : [];
  assert.ok(!files.some((f) => f.startsWith(result.run_id)), "dispatcher left derivation artifacts");
});

test("missing bp3-pi extension refuses E_SETUP before any spawn", async () => {
  const repo = makeRepo();
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: writeFakePi(repo), extensionPath: "/nonexistent/bp3-pi-index.ts" });
  await assert.rejects(
    () => dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" }),
    (e) => e.code === "E_SETUP",
  );
});

test("listRuns: live runs answer at once and are never signalled (seam.2)", () => {
  const repo = makeRepo();
  execFileSync("git", ["-C", repo, "commit", "-q", "--allow-empty", "-m", "init"]);
  fs.mkdirSync(runsDir(repo), { recursive: true });
  const live = [];
  try {
    for (const n of [1, 2, 3]) {
      const runId = `R-live-${n}`;
      const child = spawn("sleep", ["30"], { stdio: "ignore" });
      live.push(child);
      const tape = path.join(repo, `live-${n}.log`);
      fs.writeFileSync(tape, JSON.stringify({ type: "message", id: `l${n}`, message: { role: "user", content: `BP3_RUN_ID=${runId} work` } }) + "\n");
      fs.writeFileSync(path.join(runsDir(repo), `${runId}.json`), JSON.stringify({
        run_id: runId, quest: "toy", state: "claimed", tape_path: tape,
        creator: { harness: "pi" }, claim: { pid: child.pid, session_id: `S-live-${n}` },
      }));
    }
    const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: "/nonexistent/pi" });
    const t0 = Date.now();
    const runs = dispatcher.listRuns("toy");
    const ms = Date.now() - t0;
    assert.equal(runs.length, 3);
    for (const r of runs) assert.equal(r.lifecycle, "active", `lifecycle for ${r.run_id}`);
    // a hang guard (R2'): the old blocking listRuns spent 5s per live run
    assert.ok(ms < 10000, `listRuns took ${ms}ms over 3 live runs`);
    for (const c of live) assert.equal(c.exitCode, null, "a live run was signalled");
  } finally {
    for (const c of live) c.kill("SIGKILL");
  }
});
