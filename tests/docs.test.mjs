import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import test from 'node:test';

const root = fileURLToPath(new URL('..', import.meta.url));
const markdown = directory => fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry =>
  entry.isDirectory() ? markdown(path.join(directory, entry.name)) :
    entry.name.endsWith('.md') ? [path.join(directory, entry.name)] : []);
const withoutFences = text => text.replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, '');
function anchors(text) {
  const seen = new Map();
  return [...withoutFences(text).matchAll(/^#{1,6}\s+(.+)$/gm)].map(([, heading]) => {
    const id = heading.toLowerCase().replace(/[^\p{L}\p{N}_\-\s]/gu, '').replace(/\s/g, '-');
    const count = seen.get(id) ?? 0;
    seen.set(id, count + 1);
    return count ? `${id}-${count}` : id;
  });
}
test('Markdown relative links and heading anchors resolve after exp moves', t => {
  let count = 0;
  for (const file of [path.join(root, 'readme.md'), ...markdown(path.join(root, 'docs'))]) {
    const body = withoutFences(fs.readFileSync(file, 'utf8'));
    for (const [, href] of body.matchAll(/\[[^\]]*\]\(([^\s)]+)\)/g)) {
      if (/^[a-z][a-z0-9+.-]*:/i.test(href)) continue;
      const [relative, fragment] = href.split('#');
      const target = relative ? path.resolve(path.dirname(file), decodeURIComponent(relative)) : file;
      assert.ok(fs.existsSync(target), `${path.relative(root, file)}: missing ${href}`);
      if (fragment && target.endsWith('.md')) assert.ok(anchors(fs.readFileSync(target, 'utf8')).includes(decodeURIComponent(fragment)), `${file}: missing anchor ${href}`);
      count++;
    }
  }
  t.diagnostic(`${count} local links checked`);
});
test('exp records have matching dates, parent Quests and unique identities', t => {
  const identities = new Set();
  for (const file of markdown(path.join(root, 'docs/exp'))) {
    const name = path.basename(file);
    assert.match(name, /^\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\.md$/);
    const metadata = JSON.parse(execFileSync('yq', ['--front-matter=extract', '-o=json', '.', file], { encoding: 'utf8' }));
    assert.equal(metadata.date, name.slice(0, 10));
    assert.ok(['proposed', 'active', 'complete'].includes(metadata.status));
    assert.ok(Number.isInteger(metadata.exp) && metadata.exp > 0);
    const quest = path.resolve(path.dirname(file), metadata.quest);
    assert.equal(path.dirname(quest), path.join(root, 'docs/quests'));
    assert.ok(fs.existsSync(quest));
    const identity = `${quest}#${metadata.exp}`;
    assert.ok(!identities.has(identity), `duplicate canonical record for ${identity}`);
    identities.add(identity);
  }
  t.diagnostic(`${identities.size} canonical exp records checked`);
});
