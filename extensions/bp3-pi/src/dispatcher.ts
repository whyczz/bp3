// bp3-pi dispatcher: spawn + handoff only. It validates
// input, loads the role file, mints a one-time link via
// `bp3 harness link mint` (the run config is the
// InitRecord-equivalent), spawns one pi child explicitly
// loaded with bp3-pi, and binds the tape via
// `bp3 harness bind-tape` (after exit, into the run
// config). The child's first action claims the link; a
// child that never claimed is claimed by the dispatcher
// fallback with the session file identity, so no worker
// is silently unsupervised. Role files route
// model/thinking into the child env (override > role >
// conductor). It owns no watchdog, no lifecycle fold,
// and no persistent writer: every run config is written
// by bp3, never by this process, and it never signals a
// pid. await_runs is a thin relay over `bp3 harness
// watch` (the sole killer); list_runs relays watch
// verdicts over run configs; release_desk relays
// `bp3 harness desk release`.

import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { validateInput, type SpawnInput } from "./contract.ts";
import { loadRole, resolveEffective, UnknownRole } from "./roles.ts";

export interface DispatcherOptions {
  cwd: string;
  bp3Bin?: string;
  piBin?: string;
  env?: NodeJS.ProcessEnv;
  rolesDir?: string;
  extensionPath?: string;
}

export interface SpawnResult {
  ok: true;
  run_id: string;
  pid: number;
  tape_path: string;
  exit_code: number | null;
  model: string;
  thinking: string | null;
  role: string | null;
}

const defaultRolesDir = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "roles");

export class TypedRefusal extends Error {
  code: string;
  facts: Record<string, unknown>;
  constructor(code: string, message: string, facts: Record<string, unknown> = {}) {
    super(message);
    this.code = code;
    this.facts = facts;
  }
}

function gitCommonDir(cwd: string): string {
  let out: string;
  try {
    out = execFileSync("git", ["-C", cwd, "rev-parse", "--git-common-dir"], { encoding: "utf8" }).trim();
  } catch {
    throw new TypedRefusal("E_NOT_FOUND", "not inside a git repository; no repo root to bind", { cwd });
  }
  return path.isAbsolute(out) ? out : path.resolve(cwd, out);
}

function gitTopLevel(cwd: string): string {
  let out: string;
  try {
    out = execFileSync("git", ["-C", cwd, "rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();
  } catch {
    throw new TypedRefusal("E_NOT_FOUND", "not inside a git repository; no repo root to bind", { cwd });
  }
  return path.isAbsolute(out) ? out : path.resolve(cwd, out);
}

// The repo root is the worktree the caller sits in, never
// the caller's cwd and never the main checkout behind the
// common dir: the worktree's bin/bp3 and desks are the ones
// the dispatcher serves. Shared quest state still resolves
// via the common dir (derivationsDir, pi-sessions).
export function resolveRepoRoot(cwd: string): string {
  return gitTopLevel(cwd);
}

export function derivationsDir(cwd: string): string {
  return path.join(gitCommonDir(cwd), "bp3", "run-lifecycle-derivations");
}

export function runsDir(cwd: string): string {
  return path.join(gitCommonDir(cwd), "bp3", "runs");
}

const defaultExtensionPath = path.join(
  path.dirname(fileURLToPath(import.meta.url)), "..", "index.ts");

export class Dispatcher {
  readonly cwd: string;
  readonly root: string;
  readonly bp3Bin: string;
  readonly piBin: string;
  readonly env: NodeJS.ProcessEnv;
  readonly rolesDir: string;
  readonly extensionPath: string;

  constructor(opts: DispatcherOptions) {
    this.cwd = opts.cwd;
    this.root = resolveRepoRoot(opts.cwd);
    this.bp3Bin = opts.bp3Bin ?? process.env.BP3_PI_BP3_BIN ?? path.join(this.root, "bin", "bp3");
    this.piBin = opts.piBin ?? process.env.BP3_PI_BIN ?? "pi";
    this.env = opts.env ?? process.env;
    this.rolesDir = opts.rolesDir ?? process.env.BP3_PI_ROLES_DIR ?? defaultRolesDir;
    this.extensionPath = opts.extensionPath ?? process.env.BP3_PI_EXTENSION ?? defaultExtensionPath;
  }

  private bp3Json(args: string[]): Record<string, unknown> {
    let out: string;
    try {
      out = execFileSync(this.bp3Bin, args, { cwd: this.root, encoding: "utf8" });
    } catch (err) {
      const e = err as NodeJS.ErrnoException & { stdout?: string };
      if (e.code === "ENOENT") {
        throw new TypedRefusal("E_BP3_UNREACHABLE", `bp3 unreachable at ${this.bp3Bin}; refusing, session unaffected`, { bp3: this.bp3Bin });
      }
      const text = (e.stdout ?? "").trim().split("\n").pop() ?? "";
      try {
        const verdict = JSON.parse(text) as Record<string, unknown>;
        if (verdict && verdict.ok === false) return verdict;
      } catch { /* fall through to the typed refusal below */ }
      throw new TypedRefusal("E_BP3_FAILED", `bp3 ${args.slice(0, 2).join(" ")} failed`, { args });
    }
    return JSON.parse(out.trim().split("\n").pop() ?? "{}") as Record<string, unknown>;
  }

  private bp3JsonEnv(args: string[], extra: NodeJS.ProcessEnv): Record<string, unknown> {
    let out: string;
    try {
      out = execFileSync(this.bp3Bin, args, {
        cwd: this.root, encoding: "utf8", env: { ...process.env, ...extra },
      });
    } catch (err) {
      const e = err as NodeJS.ErrnoException & { stdout?: string };
      if (e.code === "ENOENT") {
        throw new TypedRefusal("E_BP3_UNREACHABLE", `bp3 unreachable at ${this.bp3Bin}; refusing, session unaffected`, { bp3: this.bp3Bin });
      }
      const text = (e.stdout ?? "").trim().split("\n").pop() ?? "";
      try {
        const verdict = JSON.parse(text) as Record<string, unknown>;
        if (verdict && verdict.ok === false) return verdict;
      } catch { /* fall through */ }
      throw new TypedRefusal("E_BP3_FAILED", `bp3 ${args.slice(0, 2).join(" ")} failed`, { args });
    }
    return JSON.parse(out.trim().split("\n").pop() ?? "{}") as Record<string, unknown>;
  }

  private requireBp3(): void {
    try {
      execFileSync(this.bp3Bin, ["harness", "init-check", "--engine", "pi"], { cwd: this.root, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") {
        throw new TypedRefusal("E_BP3_UNREACHABLE", `bp3 unreachable at ${this.bp3Bin}; refusing, session unaffected`, { bp3: this.bp3Bin });
      }
      // A non-zero verdict still proves bp3 answered; blindness is a warning, never a block.
    }
  }

  async spawnRun(input: unknown): Promise<SpawnResult> {
    const req = validateInput(input);
    this.requireBp3();
    const cycle = req.cycle ?? 1;
    // Roles route model/thinking: override beats role,
    // role beats the conductor's env. The effective values
    // are what the child env and the run config carry, so
    // routing is observed, never silently inherited.
    let role;
    if (req.role !== undefined) {
      try {
        role = loadRole(this.rolesDir, req.role);
      } catch (err) {
        if (err instanceof UnknownRole) {
          throw new TypedRefusal("E_NOT_FOUND", `no role file for role: ${req.role}`, { role: req.role });
        }
        throw err;
      }
    }
    const effective = resolveEffective(req, role, this.env);
    const model = effective.model;
    const thinking = effective.thinking;
    // Setup proof before work: without the bp3-pi extension
    // file the child cannot prove its tools are loaded, so
    // refuse typed and spawn nothing unsupervised.
    if (!fs.existsSync(this.extensionPath)) {
      throw new TypedRefusal("E_SETUP", `bp3-pi extension not loaded: ${this.extensionPath}`, { extension: this.extensionPath });
    }
    // Mint before spawn: the run config exists before the
    // child does, and the run-id arrives via the claim.
    const mintArgs = ["harness", "link", "mint", "--kind", "edge",
      "--quest", req.quest, "--node", req.node, "--edge", req.edge,
      "--harness", "pi", "--model", model, "--cycle", String(cycle),
      "--desk", this.root];
    if (thinking) mintArgs.push("--thinking", thinking);
    const parentRunId = this.env.BP3_RUN_ID;
    if (parentRunId) mintArgs.push("--parent-run-id", parentRunId);
    const minted = this.bp3Json(mintArgs);
    if (minted.ok !== true) {
      throw new TypedRefusal("E_LINK_MINT", `link mint refused for ${req.quest}/${req.node}`, { verdict: minted });
    }
    const runId = String(minted.run_id);
    const token = String(minted.token);
    const sessionDir = path.join(gitCommonDir(this.cwd), "bp3", "pi-sessions", runId);
    fs.mkdirSync(sessionDir, { recursive: true });

    const args = ["-p", "--mode", "json", "--session-dir", sessionDir];
    args.push("--extension", this.extensionPath);
    args.push("--model", model);
    if (thinking) args.push("--thinking", thinking);
    if (effective.tools && effective.tools.length > 0) args.push("--tools", effective.tools.join(","));
    args.push(`Claim this link first (bp3 harness link claim ${token}), then: ${req.prompt}`);

    const childEnv: NodeJS.ProcessEnv = {
      ...this.env,
      BP3_LINK_TOKEN: token,
      BP3_QUEST: req.quest,
      BP3_NODE: req.node,
      BP3_HARNESS: "pi",
      BP3_MODEL: model,
    };
    delete childEnv.BP3_RUN_ID;
    if (thinking) childEnv.BP3_THINKING = thinking;
    else delete childEnv.BP3_THINKING;
    delete childEnv.BP3_DECIDER;

    const child = spawn(this.piBin, args, { cwd: this.root, env: childEnv, stdio: ["ignore", "pipe", "pipe"] });
    if (child.pid === undefined) {
      throw new TypedRefusal("E_SPAWN_FAILED", `could not spawn pi child (${this.piBin})`, { run_id: runId });
    }
    const pid = child.pid;
    child.stdout?.resume();
    child.stderr?.resume();
    const exited = new Promise<number | null>((resolve) => {
      child.once("error", () => resolve(null));
      child.once("exit", (code) => resolve(code));
    });

    const exitCode = await exited;
    const tapes = fs.readdirSync(sessionDir).filter((n) => n.endsWith(".jsonl")).sort();
    if (tapes.length !== 1) {
      throw new TypedRefusal("E_TAPE_BIND", `expected exactly one session tape for ${runId}, found ${tapes.length}`, { run_id: runId, tapes });
    }
    const tapePath = path.join(sessionDir, tapes[0]);
    // The child claims first; if it never did, bind its
    // session file identity here so the Run is supervised.
    const state = this.bp3Json(["harness", "link", "lookup", "--run-id", runId]);
    if (state.ok === true && state.state === "minted") {
      let sessionId: string | null = null;
      for (const line of fs.readFileSync(tapePath, "utf8").split("\n")) {
        try {
          const row = JSON.parse(line) as Record<string, unknown>;
          if (row.type === "session" && typeof row.id === "string") { sessionId = row.id; break; }
        } catch { /* keep scanning */ }
      }
      const claimArgs = ["harness", "link", "claim", token];
      if (sessionId) claimArgs.push("--session-id", sessionId);
      const claimed = this.bp3JsonEnv(claimArgs, { PI_SESSION_FILE: tapePath });
      if (claimed.ok !== true) {
        throw new TypedRefusal("E_LINK_CLAIM", `link claim refused for ${runId}`, { verdict: claimed });
      }
    }
    const bound = this.bp3Json(["harness", "bind-tape", "--run-id", runId, "--tape-path", tapePath]);
    if (bound.ok !== true) {
      throw new TypedRefusal("E_TAPE_BIND", `bind-tape refused for ${runId}`, { verdict: bound });
    }
    return { ok: true, run_id: runId, pid, tape_path: tapePath, exit_code: exitCode, model, thinking: thinking ?? null, role: req.role ?? null };
  }

  awaitRuns(runIds: string[], opts: { timeoutSeconds?: number; silenceSeconds?: number } = {}): Record<string, unknown>[] {
    this.requireBp3();
    return runIds.map((runId) => {
      const args = ["harness", "watch", "--run-id", runId,
        "--timeout-seconds", String(opts.timeoutSeconds ?? 1800),
        "--silence-seconds", String(opts.silenceSeconds ?? 600)];
      try {
        const out = execFileSync(this.bp3Bin, args, { cwd: this.root, encoding: "utf8" });
        const verdict = JSON.parse(out.trim().split("\n").pop() ?? "{}") as Record<string, unknown>;
        return { run_id: runId, ...verdict };
      } catch (err) {
        const e = err as { stdout?: string };
        try {
          const verdict = JSON.parse((e.stdout ?? "").trim().split("\n").pop() ?? "{}") as Record<string, unknown>;
          return { run_id: runId, ...verdict };
        } catch {
          throw new TypedRefusal("E_BP3_FAILED", `watch failed for ${runId}`, { run_id: runId });
        }
      }
    });
  }

  // Lifecycle words come only from bp3: a watch verdict
  // over the run config. This process folds nothing itself.
  listRuns(quest?: string): Record<string, unknown>[] {
    this.requireBp3();
    const dir = runsDir(this.cwd);
    if (!fs.existsSync(dir)) return [];
    const rows: Record<string, unknown>[] = [];
    for (const name of fs.readdirSync(dir).filter((n) => n.endsWith(".json")).sort()) {
      let cfg: Record<string, unknown>;
      try {
        cfg = JSON.parse(fs.readFileSync(path.join(dir, name), "utf8")) as Record<string, unknown>;
      } catch { continue; /* torn config: bp3's word, not ours */ }
      const creator = (cfg.creator ?? {}) as Record<string, unknown>;
      if (creator.harness !== "pi") continue;
      if (quest !== undefined && cfg.quest !== quest) continue;
      const runId = String(cfg.run_id ?? name.slice(0, -".json".length));
      const [verdict] = this.awaitRuns([runId], { timeoutSeconds: 5 });
      rows.push({ run_id: runId, lifecycle: verdict.lifecycle ?? null, harness: "pi", quest: cfg.quest ?? null });
    }
    return rows;
  }

  releaseDesk(runId: string): Record<string, unknown> {
    this.requireBp3();
    try {
      const out = execFileSync(this.bp3Bin, ["harness", "desk", "release", "--run", runId], { cwd: this.root, encoding: "utf8" });
      return JSON.parse(out.trim().split("\n").pop() ?? "{}") as Record<string, unknown>;
    } catch (err) {
      const e = err as { stdout?: string };
      try {
        return JSON.parse((e.stdout ?? "").trim().split("\n").pop() ?? "{}") as Record<string, unknown>;
      } catch {
        throw new TypedRefusal("E_BP3_FAILED", `desk release failed for ${runId}`, { run_id: runId });
      }
    }
  }
}
