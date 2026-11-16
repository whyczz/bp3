// bp3-pi suite: fake-pi + real-bp3 integration.
// Run: node --test extensions/bp3-pi/test/
// Fake-pi proves units (registration, refusals, spawn
// ordering); the real bp3 fold proves the lifecycle word.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
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
const bp3Bin = path.join(repoRoot, "_build", "default", "src", "quest", "main.exe");
const { Dispatcher, derivationsDir, resolveRepoRoot } = await import(path.join(extRoot, "src", "dispatcher.ts"));
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
fs.writeFileSync(path.join(sessionDir, "env-capture.json"), JSON.stringify({ pid: process.pid, BP3_RUN_ID: process.env.BP3_RUN_ID ?? null, BP3_MODEL: process.env.BP3_MODEL ?? null }));
`, { mode: 0o755 });
  return fake;
}

test("extension registers exactly four tools and loads fail-open", async () => {
  const tools = [];
  extension({ registerTool: (t) => tools.push(t), on: () => {} });
  assert.deepEqual(tools.map((t) => t.name).sort(), ["await_runs", "list_runs", "release_desk", "spawn_run"]);

  const [spawn] = tools.filter((t) => t.name === "spawn_run");
  const repo = makeRepo();
  // The tool itself returns a typed refusal, never a throw,
  // when bp3 cannot be reached (here: no bin/bp3 in repo).
  const refused = await spawn.execute("c", { quest: "q", exp: "e", edge: "submit", prompt: "hi" }, null, null, { cwd: repo });
  assert.equal(refused.isError, true);
  assert.equal(JSON.parse(refused.content[0].text).error.code, "E_BP3_UNREACHABLE");
  const missing = new Dispatcher({ cwd: repo, bp3Bin: "/nonexistent/bp3", piBin: "/nonexistent/pi" });
  await assert.rejects(() => missing.spawnRun({ quest: "q", exp: "e", edge: "submit", prompt: "hi" }), (e) => e.code === "E_BP3_UNREACHABLE");
});

test("hostile inputs are refused E_REFUSED_INPUT naming the key", () => {
  const base = { quest: "q", exp: "e", edge: "submit", prompt: "hi" };
  for (const [extra, key] of [
    [{ BP3_DECIDER: "x" }, "BP3_DECIDER"],
    [{ env: { A: "1" } }, "env"],
    [{ tools: ["bash"] }, "tools"],
    [{ run_id: "20260101T000000Z-submit-pi-m-c1" }, "run_id"],
    [{ runId: "x" }, "runId"],
  ]) {
    assert.throws(() => validateInput({ ...base, ...extra }), (e) => e instanceof RefusedInput && e.code === "E_REFUSED_INPUT" && e.key === key);
  }
  assert.equal(validateInput(base).prompt, "hi");
});

test("spawn path: record-init names the live pid, bind-tape pins the tape, list_runs folds finished", async () => {
  const repo = makeRepo();
  const fakePi = writeFakePi(repo);
  const nested = path.join(repo, "a", "b");
  fs.mkdirSync(nested, { recursive: true });
  assert.equal(resolveRepoRoot(nested), repo);

  const dispatcher = new Dispatcher({ cwd: nested, bp3Bin, piBin: fakePi });
  const result = await dispatcher.spawnRun({ quest: "toy", exp: "exp-1", edge: "submit", prompt: "say hi", model: "fake-model" });
  assert.equal(result.ok, true);
  assert.match(result.run_id, /-submit-pi-fake-model-c1$/);

  const dir = derivationsDir(repo);
  const logPath = path.join(dir, `${result.run_id}.jsonl`);
  const rows = fs.readFileSync(logPath, "utf8").trim().split("\n").map((l) => JSON.parse(l));
  assert.deepEqual(rows.map((r) => r.kind), ["init_record", "tape_binding"]);
  assert.equal(rows[0].pid, result.pid);
  assert.equal(rows[0].harness, "pi");
  assert.equal(rows[1].tape_path, result.tape_path);

  const capture = JSON.parse(fs.readFileSync(path.join(path.dirname(result.tape_path), "env-capture.json"), "utf8"));
  assert.equal(capture.pid, result.pid);
  assert.equal(capture.BP3_RUN_ID, result.run_id);
  assert.equal(capture.BP3_MODEL, "fake-model");

  const runs = dispatcher.listRuns("toy");
  assert.equal(runs.length, 1);
  assert.equal(runs[0].run_id, result.run_id);
  assert.equal(runs[0].lifecycle, "finished");
});

test("dispatcher writes nothing itself under run-lifecycle-derivations", async () => {
  const repo = makeRepo();
  const fakePi = writeFakePi(repo);
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: fakePi });
  const result = await dispatcher.spawnRun({ quest: "toy", exp: "exp-1", edge: "submit", prompt: "hi", model: "fake-model" });
  const dir = derivationsDir(repo);
  const files = fs.readdirSync(dir).sort();
  // Only bp3-written artifacts for this Run: the log and,
  // after the listRuns fold, the supervisor's cache.
  assert.ok(files.every((f) => f.startsWith(result.run_id)));
  assert.ok(files.includes(`${result.run_id}.jsonl`));
});
