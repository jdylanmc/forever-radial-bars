// Converts CHANGELOG.md (written by Changesets) into Changelog.lua, which the
// addon shows in its settings. The game cannot read Markdown files.
//   node scripts/build-changelog.mjs          write Changelog.lua
//   node scripts/build-changelog.mjs --check  fail if Changelog.lua is stale
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'CHANGELOG.md');
const target = path.join(root, 'Changelog.lua');

export function parseChangelog(markdown) {
  const releases = [];
  let release;
  let section;
  let entry;
  for (const line of markdown.split(/\r?\n/)) {
    const version = line.match(/^## (.+)$/);
    const heading = line.match(/^### (.+)$/);
    const bullet = line.match(/^- (?:[0-9a-f]{7,40}: )?(.*)$/);
    if (version) {
      release = { version: version[1].trim(), sections: [] };
      releases.push(release);
      section = entry = undefined;
    } else if (heading && release) {
      section = { title: heading[1].trim(), entries: [] };
      release.sections.push(section);
      entry = undefined;
    } else if (bullet && release) {
      if (!section) {
        section = { title: 'Changes', entries: [] };
        release.sections.push(section);
      }
      entry = bullet[1].trim();
      section.entries.push(entry);
    } else if (entry !== undefined && /^\s+\S/.test(line)) {
      section.entries[section.entries.length - 1] += ' ' + line.trim();
    } else if (line.trim() === '') {
      entry = undefined;
    }
  }
  return releases;
}

// Markdown emphasis and code spans have no meaning in the game's fonts.
function plain(text) {
  return text.replace(/\*\*(.+?)\*\*/g, '$1').replace(/`([^`]+)`/g, '$1');
}

function luaString(text) {
  return '"' + plain(text)
    .replace(/\\/g, '\\\\')
    .replace(/"/g, '\\"')
    .replace(/\|/g, '||')
    .replace(/\n/g, '\\n') + '"';
}

export function renderLua(releases) {
  const out = [
    '-- Generated from CHANGELOG.md by scripts/build-changelog.mjs. Do not edit.',
    'local _, ns = ...',
    '',
    'ns.CHANGELOG = {',
  ];
  for (const release of releases) {
    out.push('\t{', `\t\tversion = ${luaString(release.version)},`, '\t\tsections = {');
    for (const section of release.sections) {
      out.push('\t\t\t{', `\t\t\t\ttitle = ${luaString(section.title)},`, '\t\t\t\tentries = {');
      for (const entry of section.entries) {
        out.push(`\t\t\t\t\t${luaString(entry)},`);
      }
      out.push('\t\t\t\t},', '\t\t\t},');
    }
    out.push('\t\t},', '\t},');
  }
  out.push('}', '');
  return out.join('\n');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const lua = renderLua(parseChangelog(readFileSync(source, 'utf8')));
  if (process.argv.includes('--check')) {
    let current = '';
    try {
      current = readFileSync(target, 'utf8');
    } catch {}
    if (current !== lua) {
      console.error('Changelog.lua is out of date. Run: npm run changelog:build');
      process.exit(1);
    }
    console.log('Changelog.lua is up to date.');
  } else {
    writeFileSync(target, lua);
    console.log('Wrote Changelog.lua');
  }
}
