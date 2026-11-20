import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseChangelog, renderLua } from './build-changelog.mjs';

const sample = `# forever-radial-bars

## 0.0.2

### Patch Changes

- 6cb6f11: Fix the **wheel** in \`combat\`.
  Continues on a second line.
- Plain "quoted" entry with a | pipe.

## 0.0.1

- Entry without a section.
`;

test('parses versions, sections, and entries newest first', () => {
  const releases = parseChangelog(sample);
  assert.deepEqual(releases.map(r => r.version), ['0.0.2', '0.0.1']);
  assert.equal(releases[0].sections[0].title, 'Patch Changes');
  assert.deepEqual(releases[0].sections[0].entries, [
    'Fix the **wheel** in `combat`. Continues on a second line.',
    'Plain "quoted" entry with a | pipe.',
  ]);
  assert.equal(releases[1].sections[0].title, 'Changes');
});

test('renders escaped Lua without Markdown or commit hashes', () => {
  const lua = renderLua(parseChangelog(sample));
  assert.match(lua, /"Fix the wheel in combat\. Continues on a second line\."/);
  assert.match(lua, /"Plain \\"quoted\\" entry with a \|\| pipe\."/);
  assert.doesNotMatch(lua, /6cb6f11/);
});

test('preserves separate paragraphs in Changesets summaries and rendered Lua', () => {
  const markdown = [
    '## 0.0.2',
    '### Patch Changes',
    '- 6cb6f11: First paragraph.',
    '  ',
    '  Second paragraph.',
    '  Wrapped continuation.',
    '',
    '',
    '  Third paragraph.',
  ].join('\n');

  const releases = parseChangelog(markdown);
  assert.deepEqual(releases[0].sections[0].entries, [
    'First paragraph.\n\nSecond paragraph. Wrapped continuation.\n\nThird paragraph.',
  ]);
  assert.match(renderLua(releases),
    /"First paragraph\.\\n\\nSecond paragraph\. Wrapped continuation\.\\n\\nThird paragraph\."/);
});

test('resets paragraph continuation at bullets, sections, and releases', () => {
  const markdown = [
    '## 0.0.2',
    '### Patch Changes',
    '- First entry.',
    '  ',
    '- Next entry.',
    '  Immediate continuation.',
    '  ',
    '### Minor Changes',
    '  Not an entry.',
    '- Minor entry.',
    '  ',
    '## 0.0.1',
    '  Not an entry either.',
    '- Older entry.',
    '  Immediate older continuation.',
  ].join('\n');

  assert.deepEqual(parseChangelog(markdown), [
    {
      version: '0.0.2',
      sections: [
        { title: 'Patch Changes', entries: ['First entry.', 'Next entry. Immediate continuation.'] },
        { title: 'Minor Changes', entries: ['Minor entry.'] },
      ],
    },
    {
      version: '0.0.1',
      sections: [
        { title: 'Changes', entries: ['Older entry. Immediate older continuation.'] },
      ],
    },
  ]);
});
