// bp3-pi contract: the SpawnInput shape, the hostile-key
// refusal, and the run-id mint. Spellings reuse the quest
// vocabulary (Run, tape, desk, InitRecord); the run-id shape
// is <ts>-<edge>-<harness>-<model>-c<cycle>, opaque to every
// consumer except the dispatcher that mints it.

export interface SpawnInput {
  quest: string;
  exp: string;
  edge: string;
  prompt: string;
  role?: string;
  model?: string;
  thinking?: string;
  cycle?: number;
  cwd?: string;
}

export class RefusedInput extends Error {
  code = "E_REFUSED_INPUT";
  key: string;
  constructor(key: string) {
    super(`E_REFUSED_INPUT: caller-supplied key refused: ${key}`);
    this.key = key;
  }
}

// Keys a caller may never supply: identity is minted by the
// dispatcher, the environment is owned by the dispatcher,
// and tools widen the child beyond its role. Any BP3_* key
// is caller env widening by another spelling (BP3_DECIDER
// is the named case); refuse by the key's own name.
const REFUSED_KEYS = new Set([
  "run_id", "runId", "run-id",
  "env", "environment",
  "tools", "tool", "allowedTools", "excludeTools",
  "session_id", "sessionId", "tape_path", "tapePath",
  "pid", "desk",
]);

export function validateInput(input: unknown): SpawnInput {
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    throw new RefusedInput("(input)");
  }
  const raw = input as Record<string, unknown>;
  for (const key of Object.keys(raw)) {
    if (REFUSED_KEYS.has(key) || key.startsWith("BP3_") || key.startsWith("bp3_")) {
      throw new RefusedInput(key);
    }
    const value = raw[key];
    if (typeof value === "object" && value !== null && !Array.isArray(value)) {
      for (const inner of Object.keys(value as Record<string, unknown>)) {
        if (inner.startsWith("BP3_")) throw new RefusedInput(inner);
      }
    }
  }
  for (const field of ["quest", "exp", "edge", "prompt"] as const) {
    if (typeof raw[field] !== "string" || (raw[field] as string).trim() === "") {
      throw new RefusedInput(field);
    }
  }
  if (raw.role !== undefined && (typeof raw.role !== "string" || raw.role.trim() === "")) {
    throw new RefusedInput("role");
  }
  return raw as unknown as SpawnInput;
}

export function mintRunId(edge: string, model: string, cycle: number, now = new Date()): string {
  const ts = now.toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z");
  const modelSlug = model.replace(/[^A-Za-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "model";
  return `${ts}-${edge}-pi-${modelSlug}-c${cycle}`;
}
