# Changesets

Every user-visible change adds one file here: `npx changeset`, or write it by
hand:

```md
---
"forever-radial-bars": patch
---

Short, player-facing description of the change.
```

`patch` for fixes, `minor` for features, `major` for breaking changes to saved
settings or behavior. Merging to `main` opens a "Version Packages" pull request
that bumps the version and writes `CHANGELOG.md` and `Changelog.lua`; merging
that pull request tags and releases.
