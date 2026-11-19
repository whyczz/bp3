// bp3-pi real suite (test-pyramid js.1): fake pi children and the
// real bp3 binary, for what only real processes prove: the spawn path,
// worktree roots, watch verdicts over live and hung children, desk
// release. Fixture tier, through run-suites.
// Run: node --test extensions/bp3-pi/test/bp3-pi-real.test.mjs
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { extRoot, makeRepo, writeFakePi, writeFakePiKind, bp3 as bp3At } from "./helpers.mjs";
import { realBp3 } from "./helpers.mjs";

const bp3Bin = realBp3;
const bp3 = (cwd, args) => bp3At(bp3Bin, cwd, args);
const { Dispatcher, derivationsDir, runsDir, resolveRepoRoot } = await import(path.join(extRoot, "src", "dispatcher.ts"));
const { validateInput, RefusedInput } = await import(path.join(extRoot, "src", "contract.ts"));
const extension = (await import(path.join(extRoot, "index.ts"))).default;

test("spawn path: link claim binds the session, bind-tape pins the tape, list_runs folds finished", async () => {
  const repo = makeRepo();
  const fakePi = writeFakePi(repo);
  const nested = path.join(repo, "a", "b");
  fs.mkdirSync(nested, { recursive: true });
  assert.equal(resolveRepoRoot(nested), fs.realpathSync(repo));

  const dispatcher = new Dispatcher({ cwd: nested, bp3Bin, piBin: fakePi });
  const result = await dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "say hi", model: "fake-model" });
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
  const result = await dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" });
  assert.equal(result.ok, true);
  assert.equal(derivationsDir(nested), derivationsDir(fs.realpathSync(repo)));
  assert.ok(fs.existsSync(path.join(runsDir(repo), `${result.run_id}.json`)));
  const runs = dispatcher.listRuns("toy");
  assert.equal(runs.find((r) => r.run_id === result.run_id)?.lifecycle, "finished");

  // Outside any repository the refusal stays typed.
  const bare = fs.mkdtempSync(path.join(os.tmpdir(), "bp3-pi-nogit-"));
  assert.throws(() => resolveRepoRoot(bare), (e) => e.code === "E_NOT_FOUND");
});

test("await_runs relays watch verbatim: settled on a finished Run", async () => {
  const repo = makeRepo();
  const fakePi = writeFakePi(repo);
  const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: fakePi });
  const result = await dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" });
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
  fs.writeFileSync(path.join(derivationsDir(repo), `${runId}.jsonl`), JSON.stringify({ kind: "init_record", run_id: runId, harness: "pi", quest: "toy", node: "node-1", pid: hung.pid, tape_path: tapePath, model: "fake-model", ts: new Date().toISOString() }) + "\n");
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
  fs.writeFileSync(path.join(derivationsDir(repo), `${runId}.jsonl`), JSON.stringify({ kind: "init_record", run_id: runId, harness: "pi", quest: "toy", node: "node-1", pid: child.pid, tape_path: tapePath, model: "fake-model", ts: new Date().toISOString() }) + "\n");
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
    () => crash.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model" }),
    (e) => e.code === "E_TAPE_BIND",
  );
  for (const kind of ["malformed", "settle"]) {
    const dispatcher = new Dispatcher({ cwd: repo, bp3Bin, piBin: writeFakePiKind(repo, kind) });
    const result = await dispatcher.spawnRun({ quest: "toy", node: "node-1", edge: "handoff", prompt: "hi", model: "fake-model", cycle: kind === "malformed" ? 2 : 3 });
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
