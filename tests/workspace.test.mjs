import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = fileURLToPath(new URL('..', import.meta.url));
const desktop = { skip: process.platform !== 'darwin' };
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "bp3-workspace 'quoted-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  for (const dir of ['bin', 'scripts', 'docs/quests', 'mock-bin']) fs.mkdirSync(path.join(root, dir), { recursive: true });
  for (const file of ['bin/bp3-zellij-init', 'scripts/zellij-init.mjs']) fs.copyFileSync(path.join(repo, file), path.join(root, file));
  const quest = 'docs/quests/2026-11-05-example.md';
  fs.writeFileSync(path.join(root, quest), '---\ndate: 2026-11-05\nstatus: active\nhome_repo: bp3\n---\n# Example\n');
  const mock = `#!${process.execPath}
import fs from 'node:fs';
import path from 'node:path';
const name = path.basename(process.argv[1]);
const args = process.argv.slice(2);
fs.appendFileSync(process.env.MOCK_LOG, JSON.stringify({ name, args }) + '\\n');
if (name === 'zellij' && args[0] === 'list-sessions') {
  process.stdout.write(process.env.MOCK_SESSIONS ?? '');
  process.exit(Number(process.env.MOCK_LIST_STATUS ?? 0));
}
if (process.env.MOCK_FAIL === name) process.exit(1);
if (name === 'pi') console.log(JSON.stringify({ args, session: process.env.BP3_SESSION,
  quest: process.env.BP3_QUEST_FILE, prompt: fs.readFileSync(args.find(a => a.startsWith('@')).slice(1), 'utf8') }));
`;
  // .mjs entrypoints via symlinks keep ESM syntax valid without package metadata.
  fs.writeFileSync(path.join(root, 'mock-bin/mock.mjs'), mock, { mode: 0o700 });
  for (const name of ['open', 'zellij', 'pi']) fs.symlinkSync('mock.mjs', path.join(root, 'mock-bin', name));
  const env = { ...process.env, PATH: `${path.join(root, 'mock-bin')}:${process.env.PATH}`, MOCK_LOG: path.join(root, 'calls') };
  delete env.BP3_RUN;
  const run = (args = [quest, 'hello'], extra = {}) => spawnSync('/bin/bash', [path.join(root, 'bin/bp3-zellij-init'), ...args], { cwd: root, env: { ...env, ...extra }, encoding: 'utf8' });
  const calls = () => fs.existsSync(env.MOCK_LOG) ? fs.readFileSync(env.MOCK_LOG, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
  return { root, quest, env, run, calls };
}

test('help has no desktop side effects', t => {
  const f = fixture(t);
  assert.equal(f.run(['--help']).status, 0);
  assert.deepEqual(f.calls(), []);
  assert.equal(fs.existsSync(path.join(f.root, '.bp3')), false);
});
test('new workspace preserves literal prompt, private files, and session binding', desktop, t => {
  const f = fixture(t);
  const prompt = 'quotes \'"; $(touch INJECTED) `touch ALSO_INJECTED`\nContinue, but do not push.';
  const result = f.run(['example', prompt]);
  assert.equal(result.status, 0, result.stderr);
  const receipt = JSON.parse(result.stdout);
  const state = receipt.state_dir;
  assert.equal(fs.statSync(state).mode & 0o777, 0o700);
  for (const name of fs.readdirSync(state)) assert.equal(fs.statSync(path.join(state, name)).mode & 0o777, 0o600);
  assert.equal(fs.readFileSync(path.join(state, 'prompt.md'), 'utf8'), prompt);
  const pi = spawnSync('/bin/sh', [path.join(state, 'controller.sh')], { env: f.env, cwd: f.root, encoding: 'utf8' });
  assert.equal(pi.status, 0, pi.stderr);
  const observed = JSON.parse(pi.stdout);
  assert.equal(observed.prompt, prompt);
  assert.equal(observed.session, receipt.session);
  assert.equal(observed.quest, fs.realpathSync(path.join(f.root, f.quest)));
  assert.equal(fs.existsSync(path.join(f.root, 'INJECTED')), false);
  assert.equal(fs.existsSync(path.join(f.root, 'ALSO_INJECTED')), false);
  const launch = f.calls().find(c => c.name === 'zellij' && c.args.includes('--create-background'));
  assert.ok(launch.args.includes(receipt.session));
  const window = f.calls().find(c => c.name === 'open' && c.args[0] === '-na');
  assert.ok(window.args.includes('-e'));
  assert.ok(window.args.includes('--window-save-state=never'), 'dedicated macOS instance must not restore all saved windows');
  assert.equal(JSON.stringify(f.calls()).includes(prompt), false);
  assert.equal(fs.existsSync(path.join(f.root, '.bp3/board.sqlite')), false);
});
test('existing reservation refuses respawn and preserves original prompt', desktop, t => {
  const f = fixture(t);
  const first = f.run();
  assert.equal(first.status, 0, first.stderr);
  const before = f.calls().filter(c => c.args.includes('--create-background')).length;
  const second = f.run([f.quest, 'different prompt']);
  assert.equal(second.status, 1);
  assert.match(second.stderr, /already reserved/);
  assert.equal(f.calls().filter(c => c.args.includes('--create-background')).length, before);
  assert.equal(fs.readFileSync(path.join(JSON.parse(first.stdout).state_dir, 'prompt.md'), 'utf8'), 'hello');
});
test('live or resurrectable session refuses a new Controller', desktop, t => {
  const f = fixture(t);
  const first = f.run();
  assert.equal(first.status, 0, first.stderr);
  const receipt = JSON.parse(first.stdout);
  fs.rmSync(receipt.state_dir, { recursive: true });
  const second = f.run(undefined, { MOCK_SESSIONS: `${receipt.session} (EXITED)\n` });
  assert.equal(second.status, 1);
  assert.match(second.stderr, /session already exists/);
  assert.equal(fs.existsSync(receipt.state_dir), false);
});
test('ambiguous external failure retains reservation and does not open Ghostty', desktop, t => {
  const f = fixture(t);
  const first = f.run(undefined, { MOCK_FAIL: 'zellij' });
  assert.equal(first.status, 1);
  assert.equal(f.calls().filter(c => c.args[0] === '-na').length, 0);
  assert.equal(fs.readdirSync(path.join(f.root, '.bp3/sessions')).length, 1);
  const retry = f.run();
  assert.equal(retry.status, 1);
  assert.match(retry.stderr, /already reserved/);
});
test('cannot list is not interpreted as no sessions; known empty listing is accepted', desktop, t => {
  const f = fixture(t);
  assert.equal(f.run(undefined, { MOCK_LIST_STATUS: '1', MOCK_SESSIONS: 'permission denied' }).status, 1);
  assert.equal(fs.existsSync(path.join(f.root, '.bp3')), false);
  const empty = f.run(undefined, { MOCK_LIST_STATUS: '1', MOCK_SESSIONS: 'No active zellij sessions found.\n' });
  assert.equal(empty.status, 0, empty.stderr);
});
test('foreign Quest, empty prompt and Worker invocation are refused', desktop, t => {
  const f = fixture(t);
  assert.equal(f.run([f.quest, ' ']).status, 1);
  fs.writeFileSync(path.join(f.root, 'foreign.md'), '# foreign');
  assert.equal(f.run(['foreign.md', 'hello']).status, 1);
  assert.equal(f.run(undefined, { BP3_RUN: 'worker' }).status, 1);
  assert.deepEqual(f.calls(), []);
});
test('symlinked workspace storage refuses writes', desktop, t => {
  const f = fixture(t);
  const outside = path.join(f.root, 'outside');
  fs.mkdirSync(outside);
  fs.symlinkSync(outside, path.join(f.root, '.bp3'));
  assert.equal(f.run().status, 1);
  assert.deepEqual(fs.readdirSync(outside), []);
});
