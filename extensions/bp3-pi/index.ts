// bp3-pi extension (dogfood.2 component A): fail-open,
// exactly four conductor tools, no proof writing. Loading
// never throws and never touches disk; with bp3 unreachable
// the session still works and each tool refuses with a
// typed error. Lifecycle, settle truth, and kills belong
// to the supervisor/watch; run-ids are minted by bp3 at
// link mint and never parsed here.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Dispatcher, TypedRefusal } from "./src/dispatcher.ts";
import { RefusedInput } from "./src/contract.ts";

type ToolResult = {
  content: { type: "text"; text: string }[];
  details: Record<string, unknown>;
  isError?: boolean;
};

function ok(payload: Record<string, unknown>): ToolResult {
  return { content: [{ type: "text", text: JSON.stringify(payload) }], details: payload };
}

function refused(err: unknown): ToolResult {
  if (err instanceof RefusedInput) {
    const payload = { ok: false, error: { code: err.code, facts: { key: err.key }, guidance: err.message } };
    return { content: [{ type: "text", text: JSON.stringify(payload) }], details: payload, isError: true };
  }
  if (err instanceof TypedRefusal) {
    const payload = { ok: false, error: { code: err.code, facts: err.facts, guidance: err.message } };
    return { content: [{ type: "text", text: JSON.stringify(payload) }], details: payload, isError: true };
  }
  const payload = { ok: false, error: { code: "E_BP3_PI", facts: {}, guidance: String(err) } };
  return { content: [{ type: "text", text: JSON.stringify(payload) }], details: payload, isError: true };
}

const SPAWN_PARAMS = {
  type: "object",
  additionalProperties: true,
  required: ["quest", "node", "edge", "prompt"],
  properties: {
    quest: { type: "string", description: "Quest slug the child Run belongs to" },
    node: { type: "string", description: "Node id the child Run belongs to" },
    edge: { type: "string", description: "FSM edge the child will call (e.g. handoff)" },
    prompt: { type: "string", description: "Task prompt for the pi child" },
    role: { type: "string", description: "Role name; routing only, never a proof input" },
    model: { type: "string", description: "Model override; beats the conductor's model" },
    thinking: { type: "string", description: "Thinking level override" },
    cycle: { type: "number", description: "Cycle number for the minted run-id" },
  },
};

export default function bp3Pi(pi: ExtensionAPI): void {
  const dispatcherFor = (cwd: string) => new Dispatcher({ cwd });

  pi.registerTool({
    name: "spawn_run",
    label: "Spawn Run",
    description: "Spawn one supervised pi child: link mint before spawn, the child claims first, bind-tape after exit. Example: spawn_run({quest, node, edge:\"handoff\", prompt})",
    parameters: SPAWN_PARAMS as never,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      try {
        return ok({ ...(await dispatcherFor(ctx.cwd).spawnRun(params)) });
      } catch (err) {
        return refused(err);
      }
    },
  });

  pi.registerTool({
    name: "await_runs",
    label: "Await Runs",
    description: "Block on Runs via bp3 harness watch (sole TERM/KILL owner); outcome relayed verbatim. Example: await_runs({run_ids:[run_id]})",
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["run_ids"],
      properties: {
        run_ids: { type: "array", items: { type: "string" }, description: "Run-ids returned by spawn_run" },
        timeout_seconds: { type: "number", description: "Overall watch timeout" },
        silence_seconds: { type: "number", description: "Silence budget before watch escalates" },
      },
    } as never,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      try {
        const p = params as { run_ids: string[]; timeout_seconds?: number; silence_seconds?: number };
        return ok({ ok: true, runs: dispatcherFor(ctx.cwd).awaitRuns(p.run_ids, { timeoutSeconds: p.timeout_seconds, silenceSeconds: p.silence_seconds }) });
      } catch (err) {
        return refused(err);
      }
    },
  });

  pi.registerTool({
    name: "list_runs",
    label: "List Runs",
    description: "List pi Runs with the supervisor's derived lifecycle (folded from run-lifecycle-derivations). Example: list_runs({quest})",
    parameters: {
      type: "object",
      additionalProperties: false,
      properties: { quest: { type: "string", description: "Optional quest slug filter" } },
    } as never,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      try {
        const p = params as { quest?: string };
        return ok({ ok: true, runs: dispatcherFor(ctx.cwd).listRuns(p.quest) });
      } catch (err) {
        return refused(err);
      }
    },
  });

  pi.registerTool({
    name: "release_desk",
    label: "Release Desk",
    description: "Release a Run's desk via bp3 harness desk release; a dirty desk is refused by bp3. Example: release_desk({run_id})",
    parameters: {
      type: "object",
      additionalProperties: false,
      required: ["run_id"],
      properties: { run_id: { type: "string", description: "Run-id whose desk to release" } },
    } as never,
    async execute(_id, params, _signal, _onUpdate, ctx) {
      try {
        const p = params as { run_id: string };
        return ok({ ...(dispatcherFor(ctx.cwd).releaseDesk(p.run_id) as Record<string, unknown>) });
      } catch (err) {
        return refused(err);
      }
    },
  });
}
