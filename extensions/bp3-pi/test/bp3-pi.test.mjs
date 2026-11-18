// bp3-pi suite: fake-pi + real-bp3 integration.
// Run: node --test extensions/bp3-pi/test/
// Fake-pi proves units (registration, refusals, spawn
// ordering); the real bp3 fold proves the lifecycle word.
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const extRoot = fileURLToPath(new URL("..", import.meta.url));
const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
// The raw binary, not bin/bp3: the shim pins BP3_ROOT to
// the bp3 repo, while the binary resolves its store from
// the caller's repo (cwd) — the shape under test here.
const bp3Bin = path.join(repoRoot, "_build", "default", "src", "graph", "main.exe");
const { Dispatcher, derivationsDir, runsDir, resolveRepoRoot } = await import(path.join(extRoot, "src", "dispatcher.ts"));
const { validateInput, RefusedInput } = await import(path.join(extRoot, "src", "contract.ts"));
const extension = (await import(path.join(extRoot, "index.ts"))).default;

function makeRepo() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bp3-pi-test-"));
  execFileSync("git", ["init", "-q", dir]);
  execFileSync("git", ["-C", dir, "config", "user.email", "test@example.com"]);
  execFileSync("git", ["-C", dir, "config", "user.name", "test"]);
  return dir;
}

function writeFakePi(dir) {
  const fake = path.join(dir, "fake-pi.mjs");
  fs.writeFileSync(fake, `#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
const args = process.argv.slice(2);
const sessionDir = args[args.indexOf("--session-dir") + 1];
await new Promise((r) => setTimeout(r, 25));
fs.mkdirSync(sessionDir, { recursive: true });
const ts = new Date().toISOString();
const lines = [
  { type: "session", version: 3, id: "fake-session", timestamp: ts, cwd: process.cwd() },
  { type: "message", id: "a1", parentId: null, timestamp: ts, message: { role: "user", content: args[args.length - 1], timestamp: Date.now() } },
  { type: "message", id: "b2", parentId: "a1", timestamp: ts, message: { role: "assistant", content: [{ type: "text", text: "done" }], provider: "fake", model: "fake-model", usage: { input: 1, output: 1, totalTokens: 2 }, stopReason: "stop", timestamp: Date.now() } },
];
fs.writeFileSync(path.join(sessionDir, "tape.jsonl"), lines.map((l) => JSON.stringify(l)).join("\\n") + "\\n");
fs.writeFileSync(path.join(sessionDir, "env-capture.json"), JSON.stringify({ pid: process.pid, BP3_RUN_ID: process.env.BP3_RUN_ID ?? null, BP3_LINK_TOKEN: process.env.BP3_LINK_TOKEN ?? null, BP3_MODEL: process.env.BP3_MODEL ?? null, BP3_THINKING: process.env.BP3_THINKING ?? null, argv: args }));
`, { mode: 0o755 });
  return fake;
}

function writeFakePiKind(dir, kind) {
  const fake = path.join(dir, `fake-pi-${kind}.mjs`);
  const bodies = {
    crash: `process.exit(1);`,
    malformed: `
fs.mkdirSync(sessionDir, { recursive: true });
fs.writeFileSync(path.join(sessionDir, "tape.jsonl"), "not json at all\\n");`,
    settle: `
fs.mkdirSync(sessionDir, { recursive: true });
const ts = new Date().toISOString();
const lines = [
  { type: "session", version: 3, id: "fake-session", timestamp: ts, cwd: process.cwd() },
  { type: "message", id: "s1", parentId: null, timestamp: ts, message: { role: "assistant", content: [{ type: "text", text: "run_settled by myself" }], stopReason: "error", timestamp: Date.now() } },
];
fs.writeFileSync(path.join(sessionDir, "tape.jsonl"), lines.map((l) => JSON.stringify(l)).join("\\n") + "\\n");`,
  };
  fs.writeFileSync(fake, `#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
const args = process.argv.slice(2);
const sessionDir = args[args.indexOf("--session-dir") + 1];
${bodies[kind]}
`, { mode: 0o755 });
  return fake;
}

function bp3(cwd, args) {
  const out = execFileSync(bp3Bin, args, { cwd, encoding: "utf8" });
  return JSON.parse(out.trim().split("\\n").pop() ?? "{}");
}

test("extension registers exactly four tools and loads fail-open", async () => {
  const tools = [];
  extension({ registerTool: (t) => tools.push(t), on: () => {} });
  assert.deepEqual(tools.map((t) => t.name).sort(), ["await_runs", "list_runs", "release_desk", "spawn_run"]);

  const [spawn] = tools.filter((t) => t.name === "spawn_run");
  const repo = makeRepo();
  // The tool itself returns a typed refusal, never a throw,
  // when bp3 cannot be reached (here: no bin/bp3 in repo).
  const refused = await spawn.execute("c", { graph: "g", node: "e", edge: "handoff", prompt: "hi" }, null, null, { cwd: repo });
  assert.equal(refused.isError, true);
  assert.equal(JSON.parse(refused.content[0].text).error.code, "E_BP3_UNREACHABLE");
  const missing = new Dispatcher({ cwd: repo, bp3Bin: "/nonexistent/bp3", piBin: "/nonexistent/pi" });
  await assert.rejects(() => missing.spawnRun({ graph: "g", node: "e", edge: "handoff", prompt: "hi" }), (e) => e.code === "E_BP3_UNREACHABLE");
});

test("hostile inputs are refused E_REFUSED_INPUT naming the key", () => {
  const base = { graph: "g", node: "e", edge: "handoff", prompt: "hi" };
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

test("spawn path: link claim binds the session, bind-tape pins the tape, list_runs folds finished", async () => {
  const repo = makeRepo();
  const fakePi = writeFakePi(repo);
  const nested = path.join(repo, "a", "b");
  fs.mkdirSync(nested, { recursive: true });
  assert.equal(resolveRepoRoot(nested), fs.realpathSync(repo));

  const dispatcher = new Dispatcher({ cwd: nested, bp3Bin, piBin: fakePi });
  const result = await dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "say hi", model: "fake-model" });
  assert.equal(result.ok, true);
  assert.match(result.run_id, /-handoff-pi-fake-model-c1$/);

  const cfg = JSON.parse(fs.readFileSync(path.join(runsDir(repo), `${result.run_id}.json`), "utf8"));
  assert.equal(cfg.state, "claimed");
  assert.equal(cfg.creator.harness, "pi");
  assert.equal(cfg.claim.session_id, "fake-session");
  assert.equal(cfg.tape_path, result.tape_path);

  const capture = JSON.parse(fs.readFileSync(path.join(path.dirname(result.tape_path), "env-capture.json"), "utf8"));
  assert.equal(capture.pid, result.pid);
  assert.equal(capture.BP3_RUN_ID, null);
  assert.match(capture.BP3_LINK_TOKEN, /^bp3link_/);
  assert.ok(capture.argv.includes("--extension"), "child explicitly loaded with bp3-pi");
  assert.equal(capture.BP3_MODEL, "fake-model");

  const runs = dispatcher.listRuns("toy");
  assert.equal(runs.length, 1);
  assert.equal(runs[0].run_id, result.run_id);
  assert.equal(runs[0].lifecycle, "finished");
});

test("worktree root: dispatcher serves the worktree it was spawned in, state stays shared", async () => {
  const repo = makeRepo();
  execFileSync("git", ["-C", repo, "commit", "-q", "--allow-empty", "-m", "init"]);
  const worktree = `${repo}-wt`;
  execFileSync("git", ["-C", repo, "worktree", "add", "-q", worktree]);
  const wt = fs.realpathSync(worktree);
  const nested = path.join(wt, "a", "b");
  fs.mkdirSync(nested, { recursive: true });

  // The worktree is the root from its top and from a nested
  // subdir; the main checkout still resolves to itself.
  assert.equal(resolveRepoRoot(wt), wt);
  assert.equal(resolveRepoRoot(nested), wt);
  assert.equal(resolveRepoRoot(repo), fs.realpathSync(repo));

  // No BP3_PI_BP3_BIN pin: the binary resolves under the
  // worktree, so link mint reaches the worktree's bp3.
  const unpinned = new Dispatcher({ cwd: nested, piBin: "/nonexistent/pi" });
  assert.equal(unpinned.root, wt);
  assert.equal(unpinned.bp3Bin, path.join(wt, "bin", "bp3"));

  // A spawn from the worktree finishes, and its derivation
  // log lands in the shared common-dir store, not the worktree.
  const fakePi = writeFakePi(repo);
  const dispatcher = new Dispatcher({ cwd: nested, bp3Bin, piBin: fakePi });
  const result = await dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" });
  assert.equal(result.ok, true);
  assert.equal(derivationsDir(nested), derivationsDir(fs.realpathSync(repo)));
  assert.ok(fs.existsSync(path.join(runsDir(repo), `${result.run_id}.json`)));
  const runs = dispatcher.listRuns("toy");
  assert.equal(runs.find((r) => r.run_id === result.run_id)?.lifecycle, "finished");

  // Outside any repository the refusal stays typed.
  const bare = fs.mkdtempSync(path.join(os.tmpdir(), "bp3-pi-nogit-"));
  assert.throws(() => resolveRepoRoot(bare), (e) => e.code === "E_NOT_FOUND");
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
  const roled = await dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", role: "scout" });
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
  const overridden = await dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", role: "scout", model: "override-model", thinking: "max", cycle: 2 });
  capture = JSON.parse(fs.readFileSync(path.join(path.dirname(overridden.tape_path), "env-capture.json"), "utf8"));
  assert.equal(capture.BP3_MODEL, "override-model");
  assert.equal(capture.BP3_THINKING, "max");
  cfg = JSON.parse(fs.readFileSync(path.join(runsDir(repo), `${overridden.run_id}.json`), "utf8"));
  assert.equal(cfg.creator.model, "override-model");
  assert.equal(cfg.creator.thinking, "max");

  // No role: the conductor's env is the last resort, still explicit.
  const plain = await dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", cycle: 3 });
  capture = JSON.parse(fs.readFileSync(path.join(path.dirname(plain.tape_path), "env-capture.json"), "utf8"));
  assert.equal(capture.BP3_MODEL, "conductor-model");
  assert.equal(capture.BP3_THINKING, "low");

  // The bundled role files parse to the decided cast.
  const bundled = new Dispatcher({ cwd: repo, bp3Bin, piBin: fakePi, env });
  const authored = await bundled.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", role: "author", cycle: 4 });
  assert.equal(authored.model, "openai/gpt-6.1-sol");
  assert.equal(authored.thinking, "medium");

  await assert.rejects(
    () => dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", role: "nope", cycle: 5 }),
    (e) => e.code === "E_NOT_FOUND",
  );
});

test("await_runs relays watch verbatim: settled on a finished Run", async () => {
  const repo = makeRepo();
  const fakePi = writeFakePi(repo);
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: fakePi });
  const result = await dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" });
  const [verdict] = dispatcher.awaitRuns([result.run_id], { timeoutSeconds: 5, silenceSeconds: 5 });
  assert.equal(verdict.ok, true);
  assert.equal(verdict.outcome, "settled");
  assert.equal(verdict.settled, true);
  assert.equal(verdict.lifecycle, "finished");
});

test("await_runs: hung child is killed by watch alone and lands orphaned, never finished", async () => {
  const repo = makeRepo();
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: writeFakePi(repo) });
  const hung = spawn("sleep", ["30"], { stdio: "ignore" });
  const hungExit = new Promise((r) => hung.once("exit", (_c, s) => r(s)));
  const runId = "20260101T000000Z-handoff-pi-fake-model-c1";
  const tapePath = path.join(repo, "hung.jsonl");
  fs.writeFileSync(tapePath, JSON.stringify({ type: "message", id: "h1", message: { role: "user", content: "work" } }) + "\n");
  fs.mkdirSync(derivationsDir(repo), { recursive: true });
  fs.writeFileSync(path.join(derivationsDir(repo), `${runId}.jsonl`), JSON.stringify({ kind: "init_record", run_id: runId, harness: "pi", graph: "toy", node: "node-1", pid: hung.pid, tape_path: tapePath, model: "fake-model", ts: new Date().toISOString() }) + "\n");
  try {
    const [verdict] = dispatcher.awaitRuns([runId], { timeoutSeconds: 15, silenceSeconds: 1 });
    assert.equal(verdict.outcome, "watchdog_killed");
    assert.equal(verdict.settled, false);
    assert.equal(verdict.lifecycle, "orphaned");
    const signal = await Promise.race([hungExit, new Promise((r) => setTimeout(() => r(null), 2000))]);
    assert.ok(signal === "SIGTERM" || signal === "SIGKILL", `hung child exited by watch signal, got ${signal}`);
  } finally {
    try { process.kill(hung.pid, "SIGKILL"); } catch { /* already reaped by watch */ }
  }
});

test("await_runs: closed-not-exited suspends the silence kill; the timeout still applies", async () => {
  const repo = makeRepo();
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: writeFakePi(repo) });
  const child = spawn("sleep", ["30"], { stdio: "ignore" });
  const runId = "20260101T000001Z-handoff-pi-fake-model-c1";
  const tapePath = path.join(repo, "closed.jsonl");
  fs.writeFileSync(tapePath, [
    JSON.stringify({ type: "message", id: "c1", message: { role: "user", content: "work" } }),
    JSON.stringify({ type: "session_closed", id: "c2" }),
  ].join("\n") + "\n");
  fs.mkdirSync(derivationsDir(repo), { recursive: true });
  fs.writeFileSync(path.join(derivationsDir(repo), `${runId}.jsonl`), JSON.stringify({ kind: "init_record", run_id: runId, harness: "pi", graph: "toy", node: "node-1", pid: child.pid, tape_path: tapePath, model: "fake-model", ts: new Date().toISOString() }) + "\n");
  try {
    const [verdict] = dispatcher.awaitRuns([runId], { timeoutSeconds: 3, silenceSeconds: 1 });
    assert.equal(verdict.outcome, "timeout");
    assert.equal(verdict.settled, false);
    process.kill(child.pid, 0); // still alive: watch did not kill a closed child
  } finally {
    try { process.kill(child.pid, "SIGKILL"); } catch { /* test cleanup only */ }
  }
});

test("fake-pi failure kinds: crash refuses the bind; malformed and self-settled tapes never finish", async () => {
  const repo = makeRepo();
  const crash = new Dispatcher({ cwd: repo, bp3Bin, piBin: writeFakePiKind(repo, "crash") });
  await assert.rejects(
    () => crash.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" }),
    (e) => e.code === "E_TAPE_BIND",
  );
  for (const kind of ["malformed", "settle"]) {
    const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: writeFakePiKind(repo, kind) });
    const result = await dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model", cycle: kind === "malformed" ? 2 : 3 });
    const runs = dispatcher.listRuns("toy");
    const mine = runs.find((r) => r.run_id === result.run_id);
    assert.ok(mine, `${kind}: run listed`);
    assert.notEqual(mine.lifecycle, "finished", `${kind}: never finished`);
  }
});

test("release_desk: dirty desk refused and preserved; clean desk released", async () => {
  const repo = makeRepo();
  execFileSync("git", ["-C", repo, "commit", "-q", "--allow-empty", "-m", "init"]);
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: writeFakePi(repo) });
  const runId = "20260101T000002Z-handoff-pi-fake-model-c1";
  const prepared = bp3(repo, ["harness", "desk", "prepare", "toy", "node-1", "--run", runId]);
  assert.equal(prepared.ok, true);
  const deskPath = path.isAbsolute(prepared.path) ? prepared.path : path.join(repo, prepared.path);
  fs.writeFileSync(path.join(deskPath, "dirty.txt"), "uncommitted\n");
  const refused = dispatcher.releaseDesk(runId);
  assert.equal(refused.ok, false);
  assert.ok(fs.existsSync(path.join(deskPath, "dirty.txt")), "dirty desk preserved");
  fs.unlinkSync(path.join(deskPath, "dirty.txt"));
  const released = dispatcher.releaseDesk(runId);
  assert.equal(released.ok, true);
  assert.equal(fs.existsSync(deskPath), false);
});

test("dispatcher never signals a pid: watch is the sole killer", () => {
  const src = fs.readFileSync(path.join(extRoot, "src", "dispatcher.ts"), "utf8");
  assert.ok(!/SIGTERM|SIGKILL|\.kill\(/.test(src), "dispatcher signals a pid");
});

test("dispatcher writes nothing itself: the run config is bp3-written", async () => {
  const repo = makeRepo();
  const fakePi = writeFakePi(repo);
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: fakePi });
  const result = await dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" });
  assert.ok(fs.existsSync(path.join(runsDir(repo), `${result.run_id}.json`)));
  const dir = derivationsDir(repo);
  const files = fs.existsSync(dir) ? fs.readdirSync(dir).sort() : [];
  assert.ok(!files.some((f) => f.startsWith(result.run_id)), "dispatcher left derivation artifacts");
});

test("missing bp3-pi extension refuses E_SETUP before any spawn", async () => {
  const repo = makeRepo();
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: writeFakePi(repo), extensionPath: "/nonexistent/bp3-pi-index.ts" });
  await assert.rejects(
    () => dispatcher.spawnRun({ graph: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" }),
    (e) => e.code === "E_SETUP",
  );
});
