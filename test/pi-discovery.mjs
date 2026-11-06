// Optional integration check against the real installed Pi resource loader.
// PI_PACKAGE_ROOT=/path/to/@earendil-works/pi-coding-agent node test/pi-discovery.mjs [project]
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';

assert.ok(process.env.PI_PACKAGE_ROOT, 'set PI_PACKAGE_ROOT to an installed Pi package');
const repo = fileURLToPath(new URL('..', import.meta.url));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'bp3-pi-skills-'));
const previousHome = process.env.HOME;
process.env.HOME = scratch;
try {
  const cwd = process.argv[2] ? path.resolve(process.argv[2]) : path.join(scratch, 'project');
  if (!process.argv[2]) {
    fs.mkdirSync(cwd);
    fs.mkdirSync(path.join(cwd, '.git')); // bound project ancestor discovery
    for (const dir of ['bin', 'scripts', 'skills']) {
      fs.cpSync(path.join(repo, dir), path.join(cwd, dir), {recursive: true});
    }
    execFileSync(path.join(cwd, 'bin/bp3'), ['skills', 'install', '--harness=all']);
    const foreign = path.join(cwd, '.agents/skills/unrelated');
    fs.mkdirSync(foreign);
    fs.writeFileSync(path.join(foreign, 'SKILL.md'), '---\nname: unrelated\ndescription: Keep unrelated skills discoverable.\n---\nKeep me.\n');
  }
  const settings = JSON.parse(fs.readFileSync(path.join(cwd, '.pi/settings.json'), 'utf8'));
  const pkg = process.env.PI_PACKAGE_ROOT;
  const {DefaultPackageManager} = await import(pathToFileURL(path.join(pkg, 'dist/core/package-manager.js')));
  const {loadSkills} = await import(pathToFileURL(path.join(pkg, 'dist/core/skills.js')));
  const agentDir = path.join(scratch, '.pi/agent');
  const manager = new DefaultPackageManager({cwd, agentDir, settingsManager: {
    getGlobalSettings: () => ({}),
    getProjectSettings: () => settings,
    isProjectTrusted: () => true,
  }});
  const resolved = await manager.resolve();
  const result = loadSkills({cwd, agentDir,
    skillPaths: resolved.skills.filter(row => row.enabled).map(row => row.path), includeDefaults: false});
  assert.deepEqual(result.diagnostics, []);
  const ids = fs.readdirSync(path.join(cwd, 'skills'));
  for (const id of ids) {
    assert.equal(result.skills.find(skill => skill.name === id)?.filePath, path.join(cwd, '.pi/skills', id, 'SKILL.md'));
    assert.ok(fs.existsSync(path.join(cwd, '.agents/skills', id, 'SKILL.md')), 'Codex/Muse copy must survive');
  }
  if (!process.argv[2]) {
    assert.ok(result.skills.some(skill => skill.name === 'unrelated'));
    assert.equal(result.skills.length, ids.length + 1);
  }
  console.log(`pi-discovery: ok (${ids.length} project skills, zero diagnostics${process.argv[2] ? '' : ', unrelated skill retained'})`);
} finally {
  process.env.HOME = previousHome;
  fs.rmSync(scratch, {recursive: true, force: true});
}
