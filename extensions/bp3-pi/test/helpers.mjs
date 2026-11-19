// Shared fixtures for the bp3-pi suites: scratch git repos, fake pi
// children, and a JSON reader over a bp3 binary (real or fake).
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const extRoot = fileURLToPath(new URL("..", import.meta.url));
export const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
// The raw binary, not bin/bp3: the shim pins BP3_ROOT to
// the bp3 repo, while the binary resolves its store from
// the caller's repo (cwd) — the shape under test here.
// test/js-unit.sh points it at a counting shim to prove the unit tier never runs it
export const realBp3 = process.env.BP3_PI_REAL_BP3 ?? path.join(repoRoot, "_build", "default", "src", "quest", "main.exe");
// test-pyramid js.1: the unit tier's bp3 replays recorded transcripts
export const fakeBp3 = path.join(repoRoot, "test", "fake-bp3", "bp3");

export function makeRepo() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "bp3-pi-test-"));
  execFileSync("git", ["init", "-q", dir]);
  execFileSync("git", ["-C", dir, "config", "user.email", "test@example.com"]);
  execFileSync("git", ["-C", dir, "config", "user.name", "test"]);
  return dir;
}

export function writeFakePi(dir) {
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

export function writeFakePiKind(dir, kind) {
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

export function bp3(bp3Bin, cwd, args) {
  const out = execFileSync(bp3Bin, args, { cwd, encoding: "utf8" });
  return JSON.parse(out.trim().split("\\n").pop() ?? "{}");
}

