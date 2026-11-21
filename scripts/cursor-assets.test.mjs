import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const toc = readFileSync(path.join(root, 'RadialBars.toc'), 'utf8');
const luaFiles = toc.split(/\r?\n/).filter(line => line.endsWith('.lua'));
const sources = luaFiles.map(file => readFileSync(path.join(root, file), 'utf8')).join('\n');
const cursor = sources.match(/local BLANK_CURSOR = "([^"]+)"/)[1]
  .replaceAll('\\\\', '/').replace('Interface/AddOns/RadialBars/', '');
const filename = cursor.endsWith('.blp') ? cursor : `${cursor}.blp`;

test('ships an uncompressed 32x32 BGRA hardware cursor with every pixel transparent', () => {
  const data = readFileSync(path.join(root, filename));
  assert.equal(data.toString('ascii', 0, 4), 'BLP2');
  assert.equal(data.readUInt32LE(4), 1);
  assert.equal(data[8], 3, 'BGRA, not DXT compression or a TGA');
  assert.equal(data[9], 8);
  assert.equal(data[10], 2, 'ARGB8888 preferred pixel format');
  assert.equal(data[11], 0, 'single cursor mip level');
  assert.equal(data.readUInt32LE(12), 32);
  assert.equal(data.readUInt32LE(16), 32);
  const offset = data.readUInt32LE(20);
  const size = data.readUInt32LE(84);
  assert.equal(offset, 1172);
  assert.equal(size, 32 * 32 * 4);
  assert.equal(data.length, offset + size);
  for (let i = 1; i < 16; i++) {
    assert.equal(data.readUInt32LE(20 + i * 4), 0);
    assert.equal(data.readUInt32LE(84 + i * 4), 0);
  }
  for (let pixel = offset; pixel < data.length; pixel += 4) assert.equal(data[pixel + 3], 0);
});

test('the TOC-loaded cursor reference remains inside the packaged Media directory', () => {
  assert.match(cursor, /^Media\/[^/]+\.blp$/);
  const metadata = readFileSync(path.join(root, '.pkgmeta'), 'utf8');
  assert.match(metadata, /^package-as: RadialBars$/m);
  const ignores = metadata.split('ignore:')[1].split(/\r?\n/)
    .map(line => line.trim().replace(/^- /, '')).filter(Boolean);
  for (const ignored of ignores) {
    assert.notEqual(filename, ignored);
    assert.ok(!filename.startsWith(`${ignored}/`));
  }
});
