import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';

const root = fs.realpathSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'));
const usage = `bp3-zellij-init QUEST PROMPT
  QUEST: an existing docs/quests/YYYY-MM-DD-slug.md file, stem, or unique slug.
  PROMPT: one quoted initial pi message (stored privately, never shell-evaluated).

macOS only; requires Ghostty, Zellij, pi, and Node. Opens a new Ghostty window
with a Controller tab. Worker launches inherit BP3_SESSION and get separate tabs.
Does not create a Board, start a runtime, change branches, or launch Workers.
Existing sessions/reservations are refused, never respawned or sent new input.
`;
const fail = message => { throw new Error(message); };
const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
function run(command, args, env = process.env) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 15000, env });
  // Do not print argv or arbitrary subprocess diagnostics: prompts can be private.
  if (result.error || result.status !== 0) fail(`${path.basename(command)} failed; inspect workspace before retrying`);
  return result.stdout.trim();
}
function executable(name) {
  for (const directory of (process.env.PATH ?? '').split(path.delimiter)) {
    const candidate = path.resolve(directory, name);
    try { fs.accessSync(candidate, fs.constants.X_OK); if (fs.statSync(candidate).isFile()) return candidate; } catch {}
  }
  fail(`${name} is not on PATH`);
}
function questFile(value) {
  const directory = path.join(root, 'docs/quests');
  let candidate = path.resolve(value);
  if (!fs.existsSync(candidate)) {
    const matches = fs.readdirSync(directory).filter(name =>
      name === `${value}.md` || name === value || name.endsWith(`-${value}.md`));
    if (matches.length !== 1) fail('QUEST must resolve to exactly one existing Quest file');
    candidate = path.join(directory, matches[0]);
  }
  const real = fs.realpathSync(candidate);
  if (path.dirname(real) !== fs.realpathSync(directory) ||
      !/^\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\.md$/.test(path.basename(real)) ||
      !fs.statSync(real).isFile()) fail('QUEST must be a dated file in this repo’s docs/quests/');
  return real;
}
function directory(name) {
  try { fs.mkdirSync(name, { mode: 0o700 }); } catch (error) { if (error.code !== 'EEXIST') throw error; }
  if (!fs.lstatSync(name).isDirectory()) fail('workspace parent must be a real directory, not a symlink');
}
function main(args) {
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) { console.log(usage); return; }
  if (args.length !== 2 || args.some(value => !value.trim())) fail(usage);
  if (process.env.BP3_RUN !== undefined) fail('workspace initialization is unavailable to Workers');
  if (process.platform !== 'darwin') fail('Ghostty workspace initialization currently supports macOS only');
  const quest = questFile(args[0]);
  const zellij = executable('zellij');
  const pi = executable('pi');
  const open = executable('open');
  run(open, ['-Ra', 'Ghostty']); // Locate app; do not open a window during preflight.
  const slug = path.basename(quest, '.md').slice(11);
  const hash = createHash('sha256').update(`${root}\0${quest}`).digest('hex').slice(0, 10);
  const session = `bp3-${slug.slice(0, 48)}-${hash}`;
  const listing = spawnSync(zellij, ['list-sessions', '--short', '--no-formatting'], { encoding: 'utf8', timeout: 15000 });
  const noSessions = listing.status === 1 && /^No active (zellij )?sessions(?: found)?\.?$/i.test(`${listing.stdout ?? ''}${listing.stderr ?? ''}`.trim());
  if (listing.error || (listing.status !== 0 && !noSessions)) fail('cannot inspect Zellij sessions; nothing launched');
  if ((listing.stdout ?? '').split('\n').some(line => line.trim().split(/\s+/)[0] === session))
    fail(`session already exists: ${session}; attach explicitly, do not replay the prompt`);
  directory(path.join(root, '.bp3'));
  directory(path.join(root, '.bp3/sessions'));
  const state = path.join(root, '.bp3/sessions', session);
  try { fs.mkdirSync(state, { mode: 0o700 }); } catch (error) {
    if (error.code === 'EEXIST') fail(`workspace already reserved: ${state}; inspect it, do not respawn`);
    throw error;
  }
  // The directory is an atomic local reservation, not Board truth. Keep it on
  // every failure after this point: an external launch may already have happened.
  const save = (name, text) => fs.writeFileSync(path.join(state, name), text, { flag: 'wx', mode: 0o600 });
  save('prompt.md', args[1]);
  save('instructions.md', `You are the Controller for ${path.relative(root, quest)} in this repo.
Read that Quest and its linked exp records before acting. The user's initial
message is the requested task, not approval to promote or push.
Your Zellij session is ${session}; keep this Controller tab separate from Workers.
BP3_QUEST_FILE identifies the Quest. BP3_SESSION binds CLI Worker launches to
this session: omit session_name to use it; a conflicting explicit name is refused.
Use normal Board/runtime operations to delegate, not pane typing or terminal
scraping. This desktop helper did not initialize a Board or runtime. Inspect
existing state; never silently rewrite historical/frozen Board bases.
`);
  save('controller.sh', `#!/bin/sh
cd ${quote(root)} || exit 1
export BP3_SESSION=${quote(session)}
export BP3_QUEST_FILE=${quote(quest)}
exec ${quote(pi)} --session-dir ${quote(path.join(state, 'pi-sessions'))} --append-system-prompt ${quote(path.join(state, 'instructions.md'))} ${quote(`@${path.join(state, 'prompt.md')}`)}
`);
  save('attach.sh', `#!/bin/sh
unset ZELLIJ ZELLIJ_SESSION_NAME
exec ${quote(zellij)} attach ${quote(session)}
`);
  save('layout.kdl', `layout {
    tab name="Controller" {
        pane size=1 borderless=true {
            plugin location="tab-bar"
        }
        pane
        pane size=1 borderless=true {
            plugin location="status-bar"
        }
    }
}
`);
  const receipt = { session, quest: path.relative(root, quest), state_dir: state, controller_tab: 'Controller', attach_argv: [zellij, 'attach', session] };
  save('reservation.json', JSON.stringify(receipt, null, 2) + '\n');
  const env = { ...process.env };
  delete env.ZELLIJ;
  delete env.ZELLIJ_SESSION_NAME;
  run(zellij, ['--layout', path.join(state, 'layout.kdl'), 'attach', '--create-background', session, '--', '/bin/sh', path.join(state, 'controller.sh')], env);
  save('session-created', 'Zellij create returned success; this is not a pi readiness receipt.\n');
  // A separate macOS instance otherwise restores ALL saved Ghostty windows.
  // Disable restoration for this instance only; never edit the user's config.
  run(open, ['-na', 'Ghostty', '--args', '--window-save-state=never', `--working-directory=${root}`, '-e', '/bin/sh', path.join(state, 'attach.sh')]);
  save('window-requested', 'Launch Services accepted the request; human visibility is not verified.\n');
  console.log(JSON.stringify({ ...receipt, window: 'requested' }, null, 2));
}
try { main(process.argv.slice(2)); } catch (error) {
  console.error(`bp3-zellij-init: ${error.message}`);
  process.exitCode = 1;
}
