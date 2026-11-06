import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { createConnection } from "node:net";
import { randomUUID } from "node:crypto";

// Transport only: Board owns policy, inbox state, fencing and retry receipts.
// Never classify terminal output or equate agent_end with settled-idle.
export default function bridge(pi: ExtensionAPI) {
  const socketPath = process.env.BP3_SOCKET;
  const auth = {
    run_id: process.env.BP3_RUN,
    generation: Number(process.env.BP3_GENERATION),
    token: process.env.BP3_TOKEN,
  };
  if (!socketPath || !auth.run_id || !auth.token) throw new Error("bp3 bridge environment missing");
  let ctx: ExtensionContext;
  let stopped = true;
  let takeover = false;
  let permission = false;
  let timer: ReturnType<typeof setInterval> | undefined;
  let queue: Promise<unknown> = Promise.resolve();
  let heartbeatPending = false;
  const offered = new Set<string>();

  function exchange(request: unknown): Promise<any> {
    return new Promise((resolve, reject) => {
      const socket = createConnection(socketPath!);
      let buffer = "";
      let complete = false;
      socket.setEncoding("utf8");
      socket.setTimeout(5000, () => socket.destroy(new Error("runtime response timeout")));
      socket.on("connect", () => socket.write(JSON.stringify({ command: "signal", request }) + "\n"));
      socket.on("data", (part) => {
        buffer += part;
        if (buffer.length > 1024 * 1024) socket.destroy(new Error("oversized response"));
        const end = buffer.indexOf("\n");
        if (end < 0) return;
        try {
          const response = JSON.parse(buffer.slice(0, end));
          complete = true;
          resolve(response);
        } catch (error) { reject(error); }
        socket.end();
      });
      socket.on("error", reject);
      socket.on("close", () => { if (!complete) reject(new Error("runtime disconnected")); });
    });
  }

  function signal(kind: string, fields: Record<string, unknown> = {}): Promise<any> {
    if (stopped) return Promise.reject(new Error("bp3 bridge stopped; inspect Board before recovery"));
    // Preserve this exact envelope across a lost response, including op_id.
    const request = {
      v: 1, op_id: randomUUID(), op: "signal", auth,
      payload: { kind, session_id: ctx.sessionManager.getSessionId(), ...fields },
    };
    const task = queue.then(async () => {
      while (!stopped) {
        let response;
        try { response = await exchange(request); }
        catch {
          ctx.ui.setStatus("bp3", "bp3: runtime disconnected; retrying receipt");
          await new Promise((resolve) => setTimeout(resolve, 1000));
          continue;
        }
        if (response.error) {
          // Protocol failures are not transport retries. Stop autonomous delivery.
          stopped = true;
          void ctx.abort();
          ctx.ui.setStatus("bp3", `bp3 fenced: ${response.error}`);
          throw new Error(response.error);
        }
        ctx.ui.setStatus("bp3", takeover ? "bp3: human takeover" : "bp3: connected");
        return response.ok;
      }
      throw new Error("bp3 bridge stopped before signal completed");
    });
    queue = task.catch(() => {});
    return task;
  }

  async function heartbeat() {
    if (heartbeatPending || stopped) return;
    heartbeatPending = true;
    try {
      const response = await signal("heartbeat");
      const message = response?.inbox;
      // Local latches protect the gap before their Board signals. If an offer
      // races takeover/prompt, leave it ambiguous on the Board; never reinject.
      if (!message || takeover || permission || stopped || offered.has(message.id)) return;
      offered.add(message.id);
      pi.sendUserMessage(`[bp3-inbox:${message.id}]\n${message.text}`, { deliverAs: "followUp" });
    } catch (error) { ctx.ui.notify(String(error), "error"); }
    finally { heartbeatPending = false; }
  }

  pi.on("session_start", async (_event, context) => {
    ctx = context;
    stopped = false;
    await signal("ready", {
      cwd: ctx.cwd, pid: process.pid,
      pane_id: process.env.ZELLIJ_PANE_ID ?? "unavailable",
      session_file: ctx.sessionManager.getSessionFile() ?? null,
      model: ctx.model?.id ?? null, provider: ctx.model?.provider ?? null,
      idle: ctx.isIdle(),
    });
    // Ready is held. Nothing starts a model until a Board inbox item exists.
    timer = setInterval(() => { void heartbeat(); }, 2000);
  });
  pi.on("input", async (event) => {
    if (event.source === "interactive") {
      takeover = true;
      await signal("took_over");
    } else if (event.source === "extension") {
      const id = /^\[bp3-inbox:([A-Za-z0-9_-]+)\]\n/.exec(event.text)?.[1];
      if (id && offered.has(id)) await signal("observed", { inbox_id: id });
    }
    return { action: "continue" };
  });
  pi.on("user_bash", async () => { takeover = true; await signal("took_over"); });
  pi.on("agent_start", async () => { await signal("busy"); });
  pi.on("agent_settled", async (_event, context) => {
    await signal("settled", { idle: context.isIdle() });
  });
  pi.on("ui_prompt_start", () => { permission = true; void signal("permission-start").catch(() => {}); });
  pi.on("ui_prompt_end", () => { permission = false; void signal("permission-end").catch(() => {}); });
  // Session navigation would discard the frozen run's context. A fresh
  // run must be explicit; this is not a resumable arbitrary pi session.
  pi.on("session_before_switch", async () => ({ cancel: true }));
  pi.on("session_before_fork", async () => ({ cancel: true }));
  pi.on("session_before_tree", async () => ({ cancel: true }));
  pi.registerCommand("bp3-release", {
    description: "Return this idle pane to bp3 after human takeover",
    handler: async (_args, context) => {
      if (!context.isIdle()) { context.ui.notify("Wait for settled-idle before release", "warning"); return; }
      await signal("release", { idle: true });
      takeover = false;
      context.ui.setStatus("bp3", "bp3: released");
    },
  });
  pi.on("cache_warming_decision", () => ({ action: "stop" }));
  pi.on("session_shutdown", async () => {
    if (timer) clearInterval(timer);
    // Shutdown must not wait forever for a dead runtime. Missing this signal is
    // safe: the runtime's heartbeat timeout independently marks the Worker stale.
    stopped = true;
  });
}
