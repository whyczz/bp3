// Adapter contract tests use a fake pi API and a real Unix socket. They do not
// claim watchability or substitute for the live pi/Zellij acceptance receipt.
import test from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import { mkdtemp, rm } from "node:fs/promises";
import bridge from "../plugins/harness-pi/bridge.ts";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function until(predicate) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await sleep(50);
  }
  assert.fail("bridge observation timed out");
}

async function fixture(t, respond = () => ({ ok: { inbox: null } })) {
  const directory = await mkdtemp("/tmp/bp3-bridge-test-");
  const socket = `${directory}/bridge.sock`;
  Object.assign(process.env, {
    BP3_SOCKET: socket, BP3_EXECUTION: "test-worker", BP3_GENERATION: "1", BP3_TOKEN: "test-only",
  });
  const requests = [];
  const server = net.createServer((client) => {
    let buffer = "";
    client.setEncoding("utf8");
    client.on("data", (chunk) => {
      buffer += chunk;
      if (!buffer.includes("\n")) return;
      const { request } = JSON.parse(buffer.slice(0, buffer.indexOf("\n")));
      requests.push(request);
      const response = respond(request);
      if (response === "disconnect") client.destroy();
      else client.end(JSON.stringify(response) + "\n");
    });
  });
  await new Promise((resolve) => server.listen(socket, resolve));
  const handlers = new Map();
  const commands = new Map();
  const messages = [];
  let aborted = false;
  const context = {
    cwd: directory, model: { id: "fake", provider: "test" },
    sessionManager: { getSessionId: () => "session", getSessionFile: () => "fixture.jsonl" },
    isIdle: () => true, abort: () => { aborted = true; },
    ui: { setStatus() {}, notify() {} },
  };
  const api = {
    on: (name, fn) => handlers.set(name, fn),
    registerCommand: (name, command) => commands.set(name, command),
    sendUserMessage: (text, options) => { messages.push({ text, options }); },
  };
  bridge(api);
  const emit = async (name, event = {}) => handlers.get(name)?.(event, context);
  t.after(async () => {
    await emit("session_shutdown");
    await new Promise((resolve) => server.close(resolve));
    await rm(directory, { recursive: true });
  });
  return { emit, handlers, commands, context, messages, requests, aborted: () => aborted };
}

test("ready holds the brief; only agent_settled advertises final idle", async (t) => {
  const f = await fixture(t);
  await f.emit("session_start");
  assert.equal(f.requests[0].payload.kind, "ready");
  assert.equal(f.handlers.has("agent_end"), false);
  await f.emit("agent_start");
  await f.emit("agent_settled");
  assert.deepEqual(f.requests.map((r) => r.payload.kind), ["ready", "busy", "settled"]);
  assert.equal(f.requests.at(-1).payload.idle, true);
  assert.equal(f.messages.length, 0);
  assert.deepEqual(await f.emit("cache_warming_decision"), { action: "stop" });
});

test("lost socket response retries the identical receipt, not a new ready", async (t) => {
  let first = true;
  const f = await fixture(t, () => {
    if (first) { first = false; return "disconnect"; }
    return { ok: { inbox: null } };
  });
  await f.emit("session_start");
  assert.equal(f.requests.length, 2);
  assert.deepEqual(f.requests[0], f.requests[1]);
});

test("Board message uses followUp, input ACK, interactive takeover and explicit release", async (t) => {
  let offered = false;
  const f = await fixture(t, (request) => {
    if (request.payload.kind === "heartbeat" && !offered) {
      offered = true;
      return { ok: { inbox: { id: "brief-test", text: "bounded brief" } } };
    }
    return { ok: { inbox: null } };
  });
  await f.emit("session_start");
  await until(() => f.messages.length === 1);
  assert.deepEqual(f.messages[0], {
    text: "[bp3-inbox:brief-test]\nbounded brief", options: { deliverAs: "followUp" },
  });
  await f.emit("input", { source: "extension", text: f.messages[0].text });
  assert.equal(f.requests.at(-1).payload.kind, "observed");
  await f.emit("input", { source: "interactive", text: "I am taking over" });
  assert.equal(f.requests.at(-1).payload.kind, "took_over");
  await f.commands.get("bp3-release").handler("", f.context);
  assert.equal(f.requests.at(-1).payload.kind, "release");
  assert.deepEqual(await f.emit("session_before_switch"), { cancel: true });
});

test("a protocol fence stops automation and aborts work", async (t) => {
  const f = await fixture(t, () => ({ error: "execution budget exhausted" }));
  await assert.rejects(f.emit("session_start"), /execution budget exhausted/);
  assert.equal(f.aborted(), true);
  assert.equal(f.messages.length, 0);
  await assert.rejects(f.commands.get("bp3-release").handler("", f.context), /bridge stopped/);
});
