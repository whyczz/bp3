// bp3-pi dispatcher: spawn + handoff only (dogfood.2
// component B). It validates input, mints the run-id,
// spawns one pi child, and hands spawn/exit facts to the
// supervisor through `bp3 harness record-init` (live pid,
// before the child's work) and `bp3 harness bind-tape`
// (after exit). It owns no watchdog, no lifecycle fold,
// and no persistent writer: every derivation row is
// written by bp3, never by this process. await_runs is a
// thin relay over `bp3 harness watch` (the sole killer);
// list_runs relays the supervisor's derived cache/verdict;
// release_desk relays `bp3 harness desk release`.

import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { mintRunId, validateInput, type SpawnInput } from "./contract.ts";

export interface DispatcherOptions {
  cwd: string;
  bp3Bin?: string;
  piBin?: string;
  env?: NodeJS.ProcessEnv;
}

export interface SpawnResult {
  ok: true;
  run_id: string;
  pid: number;
  tape_path: string;
  exit_code: number | null;
}

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

// The repo root is the main checkout that owns the common
// dir, never the caller's cwd: spawning from a nested
// subdir binds the same quest as from the root.
export function resolveRepoRoot(cwd: string): string {
  return path.dirname(gitCommonDir(cwd));
}

export function derivationsDir(cwd: string): string {
  return path.join(gitCommonDir(cwd), "bp3", "run-lifecycle-derivations");
}

export class Dispatcher {
  readonly cwd: string;
  readonly root: string;
  readonly bp3Bin: string;
  readonly piBin: string;
  readonly env: NodeJS.ProcessEnv;

  constructor(opts: DispatcherOptions) {
    this.cwd = opts.cwd;
    this.root = resolveRepoRoot(opts.cwd);
    this.bp3Bin = opts.bp3Bin ?? process.env.BP3_PI_BP3_BIN ?? path.join(this.root, "bin", "bp3");
    this.piBin = opts.piBin ?? process.env.BP3_PI_BIN ?? "pi";
    this.env = opts.env ?? process.env;
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
    const model = req.model ?? this.env.BP3_MODEL ?? "gpt-6.1-sol";
    const thinking = req.thinking ?? this.env.BP3_THINKING;
    const runId = mintRunId(req.edge, model, cycle);
    const sessionDir = path.join(gitCommonDir(this.cwd), "bp3", "pi-sessions", runId);
    fs.mkdirSync(sessionDir, { recursive: true });

    const args = ["-p", "--mode", "json", "--session-dir", sessionDir];
    if (req.model) args.push("--model", req.model);
    if (thinking) args.push("--thinking", thinking);
    args.push(req.prompt);

    const childEnv: NodeJS.ProcessEnv = {
      ...this.env,
      BP3_RUN_ID: runId,
      BP3_QUEST: req.quest,
      BP3_EXP: req.exp,
      BP3_HARNESS: "pi",
      BP3_MODEL: model,
    };
    if (thinking) childEnv.BP3_THINKING = thinking;
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

    // The InitRecord names the live pid before the child's
    // work is observed; bp3 is the only writer of the row.
    const init = this.bp3Json(["harness", "record-init", "--run-id", runId, "--harness", "pi",
      "--quest", req.quest, "--exp", req.exp, "--pid", String(pid), "--model", model]);
    if (init.ok !== true) {
      throw new TypedRefusal("E_RECORD_INIT", `record-init refused for ${runId}`, { verdict: init });
    }

    const exitCode = await exited;
    const tapes = fs.readdirSync(sessionDir).filter((n) => n.endsWith(".jsonl")).sort();
    if (tapes.length !== 1) {
      throw new TypedRefusal("E_TAPE_BIND", `expected exactly one session tape for ${runId}, found ${tapes.length}`, { run_id: runId, tapes });
    }
    const tapePath = path.join(sessionDir, tapes[0]);
    const bound = this.bp3Json(["harness", "bind-tape", "--run-id", runId, "--tape-path", tapePath]);
    if (bound.ok !== true) {
      throw new TypedRefusal("E_TAPE_BIND", `bind-tape refused for ${runId}`, { verdict: bound });
    }
    return { ok: true, run_id: runId, pid, tape_path: tapePath, exit_code: exitCode };
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

  // Lifecycle words come only from the supervisor: the
  // derived .json cache it writes, or a watch verdict it
  // returns. This process folds nothing itself.
  listRuns(quest?: string): Record<string, unknown>[] {
    this.requireBp3();
    const dir = derivationsDir(this.cwd);
    if (!fs.existsSync(dir)) return [];
    const rows: Record<string, unknown>[] = [];
    for (const name of fs.readdirSync(dir).filter((n) => n.endsWith(".jsonl")).sort()) {
      const runId = name.slice(0, -".jsonl".length);
      const logPath = path.join(dir, name);
      let initQuest: unknown = null;
      let harness: unknown = null;
      for (const line of fs.readFileSync(logPath, "utf8").split("\n")) {
        try {
          const row = JSON.parse(line) as Record<string, unknown>;
          if (row.kind === "init_record") { initQuest = row.quest ?? null; harness = row.harness ?? null; }
        } catch { /* torn tail: the fold's word, not ours */ }
      }
      if (harness !== "pi") continue;
      if (quest !== undefined && initQuest !== quest) continue;
      const cachePath = path.join(dir, `${runId}.json`);
      if (fs.existsSync(cachePath)) {
        const cache = JSON.parse(fs.readFileSync(cachePath, "utf8")) as Record<string, unknown>;
        rows.push({ run_id: runId, lifecycle: cache.lifecycle ?? null, harness, quest: initQuest });
      } else {
        const [verdict] = this.awaitRuns([runId], { timeoutSeconds: 5 });
        rows.push({ run_id: runId, lifecycle: verdict.lifecycle ?? null, harness, quest: initQuest });
      }
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
