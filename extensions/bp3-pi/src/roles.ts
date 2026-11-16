// bp3-pi roles: role files carry the child's default
// model/thinking/tools in frontmatter; the prompt body is
// the role's standing instruction. Precedence is one rule:
// spawn override beats role, role beats the conductor's own
// env (BP3_MODEL / BP3_THINKING). A child never silently
// inherits the conductor's model when a role names one.

import fs from "node:fs";
import path from "node:path";

export interface Role {
  name: string;
  model?: string;
  thinking?: string;
  tools?: string[];
  prompt: string;
}

export class UnknownRole extends Error {
  code = "E_NOT_FOUND";
  role: string;
  constructor(role: string) {
    super(`E_NOT_FOUND: no role file for role: ${role}`);
    this.role = role;
  }
}

// Frontmatter is `key: value` lines between `---` fences;
// tools is a comma-separated allowlist. No YAML dependency:
// the role vocabulary is exactly model/thinking/tools.
export function parseRole(name: string, text: string): Role {
  const role: Role = { name, prompt: text.trim() };
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!m) return role;
  role.prompt = text.slice(m[0].length).trim();
  for (const line of m[1].split(/\r?\n/)) {
    const kv = line.match(/^([A-Za-z_-]+):\s*(.*)$/);
    if (!kv) continue;
    const [, key, raw] = kv;
    const value = raw.trim().replace(/^["']|["']$/g, "");
    if (value === "") continue;
    if (key === "model") role.model = value;
    else if (key === "thinking") role.thinking = value;
    else if (key === "tools") {
      role.tools = value.split(",").map((t) => t.trim()).filter((t) => t !== "");
    }
  }
  return role;
}

export function loadRole(rolesDir: string, name: string): Role {
  // Role names are file stems; refuse path travel by name.
  if (name === "" || name.includes("/") || name.includes("\\") || name.includes("..")) {
    throw new UnknownRole(name);
  }
  const file = path.join(rolesDir, `${name}.md`);
  if (!fs.existsSync(file)) throw new UnknownRole(name);
  return parseRole(name, fs.readFileSync(file, "utf8"));
}

export interface EffectiveConfig {
  model: string;
  thinking?: string;
  tools?: string[];
  role?: Role;
}

// override > role > conductor env; model falls back to the
// dispatcher's long-standing default when nobody names one.
export function resolveEffective(
  input: { model?: string; thinking?: string },
  role: Role | undefined,
  env: NodeJS.ProcessEnv,
): EffectiveConfig {
  const model = input.model ?? role?.model ?? env.BP3_MODEL ?? "gpt-6.1-sol";
  const thinking = input.thinking ?? role?.thinking ?? env.BP3_THINKING;
  const out: EffectiveConfig = { model, tools: role?.tools, role };
  if (thinking) out.thinking = thinking;
  return out;
}
