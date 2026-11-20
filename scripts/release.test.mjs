import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { runInNewContext } from 'node:vm';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const workflow = readFileSync(path.join(root, '.github', 'workflows', 'release.yml'), 'utf8')
  .replace(/\r\n/g, '\n');
const bash = process.platform === 'win32'
  ? path.join(process.env.ProgramFiles, 'Git', 'bin', 'bash.exe')
  : 'bash';

function step(name) {
  const start = workflow.indexOf(`      - name: ${name}\n`);
  assert.notEqual(start, -1, `Missing workflow step: ${name}`);
  const next = workflow.indexOf('\n      - ', start);
  return workflow.slice(start, next === -1 ? undefined : next);
}

const tagStep = step('Tag new version');
const condition = tagStep.match(/^        if: (.+)$/m)[1];
const script = tagStep.match(/^        run: \|\n((?:          .*\n|\n)*)/m)[1]
  .split('\n').map(line => line.slice(10)).join('\n');

function shouldPrepare(refType, hasChangesets) {
  return runInNewContext(condition, {
    github: { ref_type: refType },
    steps: { changesets: { outputs: { 'has-changesets': hasChangesets } } },
  });
}

function prepare({ assets = [], status = 0, response, refType = 'branch', tagStatus = 0 } = {}) {
  const outputFile = path.join(root, 'scripts', `.release-test-${randomUUID()}.output`);
  try {
    const result = spawnSync(bash, ['--noprofile', '--norc', '-e', '-c', `
exec 3>&1
gh() {
  printf 'MOCK gh %s\\n' "$*" >&3
  printf '%s\\n' "$RELEASE_RESPONSE"
  return "$MOCK_GH_STATUS"
}
git() {
  printf 'MOCK git %s\\n' "$*" >&3
  if [ "$1" = ls-remote ]; then
    return "$MOCK_TAG_STATUS"
  fi
}
${script}`], {
      cwd: root,
      encoding: 'utf8',
      env: {
        ...process.env,
        GITHUB_REF_TYPE: refType,
        GITHUB_REF_NAME: 'v0.0.1',
        GITHUB_OUTPUT: outputFile,
        RELEASE_RESPONSE: response ?? JSON.stringify({ assets }),
        MOCK_GH_STATUS: String(status),
        MOCK_TAG_STATUS: String(tagStatus),
      },
    });
    assert.ifError(result.error);
    const outputs = existsSync(outputFile) ? readFileSync(outputFile, 'utf8') : '';
    return { ...result, output: result.stdout + result.stderr + outputs };
  } finally {
    rmSync(outputFile, { force: true });
  }
}

test('uses the Changesets v2 input and output contract', () => {
  const versionStep = step('Version pull request');
  assert.match(versionStep, /uses: changesets\/action@v2/);
  assert.match(versionStep, /^          version-script: npm run version$/m);
  assert.match(versionStep, /^          commit-message: 'chore: version packages'$/m);
  assert.match(versionStep, /^          pr-title: 'chore: version packages'$/m);
  assert.doesNotMatch(versionStep, /^          (?:version|commit|title):/m);
});

test('prepares only tags or branches with no pending Changesets', () => {
  assert.equal(shouldPrepare('branch', 'true'), false);
  assert.equal(shouldPrepare('branch', 'false'), true);
  assert.equal(shouldPrepare('branch', undefined), false);
  assert.equal(shouldPrepare('tag', undefined), true);
});

test('skips an existing release only when an uploaded nonempty ZIP exists', () => {
  const result = prepare({
    assets: [{ name: 'RadialBars-v0.0.1.zip', size: 1024, state: 'uploaded' }],
  });
  assert.equal(result.status, 0, result.output);
  assert.doesNotMatch(result.output, /package=true|MOCK git (?:fetch|checkout|tag|push)/);
});

for (const [name, assets] of [
  ['no assets', []],
  ['metadata but no ZIP', [{ name: 'release.json', size: 128, state: 'uploaded' }]],
  ['an empty ZIP', [{ name: 'RadialBars.zip', size: 0, state: 'uploaded' }]],
  ['an unfinished ZIP upload', [{ name: 'RadialBars.zip', size: 1024, state: 'starter' }]],
]) {
  test(`repackages an existing tag with ${name}`, () => {
    const result = prepare({ assets });
    assert.equal(result.status, 0, result.output);
    assert.match(result.output, /package=true/);
    assert.match(result.output, /MOCK git fetch --force origin refs\/tags\/v0\.0\.1:refs\/tags\/v0\.0\.1/);
    assert.match(result.output, /MOCK git checkout --detach v0\.0\.1/);
    assert.doesNotMatch(result.output, /MOCK git (?:tag|push)/);
  });
}

test('repackages a missing release without rewriting its existing tag', () => {
  const result = prepare({ status: 1, response: 'gh: Not Found (HTTP 404)' });
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, /package=true/);
  assert.match(result.output, /MOCK git checkout --detach v0\.0\.1/);
  assert.doesNotMatch(result.output, /MOCK git (?:tag|push)/);
});

for (const response of ['gh: Forbidden (HTTP 403)', 'gh: Server Error (HTTP 500)', 'connection refused']) {
  test(`fails closed when the release lookup fails: ${response}`, () => {
    const result = prepare({ status: 1, response });
    assert.notEqual(result.status, 0, result.output);
    assert.doesNotMatch(result.output, /package=true|MOCK git (?:fetch|checkout|tag|push)/);
  });
}

test('fails closed on a malformed successful release response', () => {
  const result = prepare({ response: 'not JSON' });
  assert.notEqual(result.status, 0, result.output);
  assert.doesNotMatch(result.output, /package=true|MOCK git (?:fetch|checkout|tag|push)/);
});

test('packages an incomplete directly triggered tag without changing tags', () => {
  const result = prepare({ refType: 'tag' });
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, /package=true/);
  assert.doesNotMatch(result.output, /MOCK git /);
});

test('creates and packages a version that has not been tagged', () => {
  const result = prepare({ tagStatus: 2 });
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, /MOCK git tag -a v0\.0\.1 -m v0\.0\.1/);
  assert.match(result.output, /MOCK git push origin v0\.0\.1/);
  assert.match(result.output, /package=true/);
  assert.doesNotMatch(result.output, /MOCK gh /);
});
