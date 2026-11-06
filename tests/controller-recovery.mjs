// Opt-in, paid live acceptance: real Worker + genuinely fresh pi Controllers.
// Only the Controller's own process group is killed. The Worker/runtime are
// siblings, and no pane contents or previous Controller transcript are read.
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { createWriteStream, existsSync } from "node:fs";
import { mkdir, writeFile, readFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { createInterface } from "node:readline";

const [directory, session, model] = process.argv.slice(2);
if (!directory || !session || !model || existsSync(directory)) {
  throw new Error("usage: node tests/controller-recovery.mjs NEW_DIRECTORY SESSION PROVIDER/MODEL");
}
const root = resolve(directory);
const board = join(root, "board.sqlite");
const binary = join(root, "genesis/bp3");
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const call = (...args) => JSON.parse(execFileSync(binary, ["--board", board, ...args], { encoding: "utf8" }));
const context = () => call("context");
function op(id, operation, payload) {
  return JSON.parse(execFileSync(binary, ["--board", board, "op", "-"], {
    encoding: "utf8", input: JSON.stringify({ v: 1, op_id: id, op: operation, payload }),
  }));
}
async function until(description, predicate, seconds = 60) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await sleep(200);
  }
  throw new Error(`timed out: ${description}`);
}
const quoted = (s) => "'" + s.replaceAll("'", "'\\''") + "'";

async function controller(phase, killAfterRead) {
  const logs = join(root, phase);
  await mkdir(logs);
  const prompt = `You are a fresh replacement bp3 Controller doing a read-only recovery check.
Your only source of truth is this command: ${quoted(binary)} --board ${quoted(board)} context
Run it with bash. Do not read code, other files, sessions, or transcripts. Do not mutate
anything, launch, answer a question, or call other commands. After reading the Board,
return ONLY a JSON object, no markdown, with: quest_id, exp_id, execution_id,
idle (integer 0 or 1, copied exactly from the execution record),
launch_required (boolean), open_question_ids (array), obligation (brief summary),
next_action (brief recommendation). Infer the current obligation from the records;
settled-idle is not completion, and an existing execution must not be duplicated.`;
  const output = createWriteStream(join(logs, "events.jsonl"));
  const errors = createWriteStream(join(logs, "stderr.log"));
  const child = spawn("pi", [
    "--print", "--mode", "json", "--model", model, "--thinking", "low",
    "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-mcp",
    "--no-context-files", "--no-approve", "--offline", "--tools", "bash",
    "--session-dir", join(logs, "sessions"), "--", prompt,
  ], { detached: true, stdio: ["ignore", "pipe", "pipe"], cwd: root });
  child.stdout.pipe(output);
  child.stderr.pipe(errors);
  let snapshot;
  let finalText;
  let killed = false;
  const failures = [];
  const lines = createInterface({ input: child.stdout });
  lines.on("line", (line) => {
    try {
      const event = JSON.parse(line);
      if (event.type === "tool_execution_end" && event.toolName === "bash" && !event.isError) {
        // This is bp3 context output, not terminal scraping. Killing after the
        // read lets the test prove exactly which obligation the dead session saw.
        const text = event.result.content.filter((p) => p.type === "text").map((p) => p.text).join("\n");
        snapshot = JSON.parse(text);
        assert.equal(snapshot.executions.length, 1);
        if (killAfterRead && !killed) {
          killed = true;
          process.kill(-child.pid, "SIGKILL");
        }
      }
      if (event.type === "message_end" && event.message?.role === "assistant") {
        const text = event.message.content.filter((p) => p.type === "text").map((p) => p.text).join("\n");
        if (text) finalText = text;
      }
    } catch (error) { failures.push(String(error)); }
  });
  const timeout = setTimeout(() => {
    failures.push("Controller exceeded 120-second deadline");
    try { process.kill(-child.pid, "SIGKILL"); } catch { /* already exited */ }
  }, 120_000);
  const exit = await new Promise((done, reject) => {
    child.on("error", reject);
    child.on("close", (code, signal) => done({ code, signal }));
  }).finally(() => clearTimeout(timeout));
  assert.deepEqual(failures, [], `Controller stream errors: ${failures}`);
  assert.ok(snapshot, "Controller must actually read bp3 context");
  await writeFile(join(logs, "snapshot.json"), JSON.stringify(snapshot, null, 2));
  if (killAfterRead) {
    assert.equal(exit.signal, "SIGKILL");
    assert.ok(killed);
    return snapshot;
  }
  assert.equal(exit.code, 0);
  const briefing = JSON.parse(finalText);
  assert.equal(briefing.quest_id, snapshot.quests[0].id);
  assert.equal(briefing.exp_id, snapshot.exps[0].id);
  assert.equal(briefing.execution_id, snapshot.executions[0].id);
  assert.equal(briefing.idle, snapshot.executions[0].idle);
  assert.equal(briefing.launch_required, false);
  assert.deepEqual(briefing.open_question_ids.sort(), snapshot.questions.filter((q) => q.state === "open").map((q) => q.id).sort());
  assert.ok(briefing.obligation && briefing.next_action);
  await writeFile(join(logs, "briefing.json"), JSON.stringify(briefing, null, 2));
  console.log(`${phase}: ${JSON.stringify(briefing)}`);
  return snapshot;
}

execFileSync("tests/start-toy", [root, session, model, "recovery"], { stdio: "inherit" });
try {
  await until("Worker ready", () => context().executions[0]?.ready === 1);
  op("recovery-deliver", "brief", { execution_id: "hello-worker" });
  await until("Worker in active tool", () => existsSync(join(root, "gate-entered")) && context().executions[0].idle === 0);
  const active = await controller("active-killed", true);
  assert.equal(active.executions[0].idle, 0);
  const activeRecovered = await controller("active-recovered", false);
  assert.equal(activeRecovered.executions[0].idle, 0);
  assert.deepEqual(activeRecovered.questions, []);
  // Release a deterministic test barrier, not a human answer or synthetic pane input.
  await writeFile(join(root, "gate-release"), "release test barrier\n");
  await until("durable pending question and settled Worker", () => {
    const state = context();
    return state.questions.some((q) => q.state === "open") && state.executions[0].idle === 1;
  });
  const blocked = await controller("blocked-killed", true);
  const blockedRecovered = await controller("blocked-recovered", false);
  assert.deepEqual(blockedRecovered.questions, blocked.questions);
  assert.equal(blockedRecovered.results.length, 0);
  const pane = JSON.parse(blockedRecovered.executions[0].endpoint).pane_id;
  execFileSync("zellij", ["--session", session, "action", "close-pane", "--pane-id", `terminal_${pane}`]);
  await until("dead Worker becomes stale without respawn", () => context().executions[0].observed === "stale", 20);
  const final = context();
  assert.equal(final.executions.length, 1);
  assert.equal(final.results.length, 0);
  assert.deepEqual(final.questions, blocked.questions);
  await writeFile(join(root, "recovery-receipt.json"), JSON.stringify(final, null, 2));
  console.log("Controller death during work and pending question; fresh-session recovery; pane death: PASS");
} finally {
  // Preserve evidence, but abandon this deliberately unanswered test exp. Use
  // only the runtime PID owned by this fixture, never a stored Worker PID.
  op("recovery-cleanup", "cancel", { execution_id: "hello-worker" });
  execFileSync("zellij", ["kill-session", session]);
  const pid = Number((await readFile(join(root, "runtime.pid"), "utf8")).trim());
  assert.equal(call("ping").pid, pid);
  process.kill(pid, "SIGTERM");
}
