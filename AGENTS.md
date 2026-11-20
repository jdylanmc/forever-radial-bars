# Agent instructions

Radial Bars is a World of Warcraft: Forever addon (interface `16001`, game
type `camelot`/`forever`, Lua 5.1). It turns action bars 2-8 into a radial
wheel opened by a hotkey. Read `README.md` for features and settings.

## Layout

| Path | Role |
| --- | --- |
| `RadialBars.toc` | Manifest; Lua load order. Version is `@project-version@`, filled by the packager from the git tag |
| `Core.lua` | Saved settings, limits, slot math, combat-safe apply, changelog formatting. Keep pure logic here so it is testable |
| `Changelog.lua` | **Generated** from `CHANGELOG.md`; never edit by hand |
| `Wheel.lua` | Secure wheel, slot buttons, hotkey trigger, visuals |
| `Settings.lua` | Options page, Changelog subpage, key capture |
| `Media/` | Textures (TGA, power-of-two, bottom-left origin) |
| `spec/` | busted unit tests; `spec/helpers/wow.lua` stubs the client API |
| `scripts/` | Node tooling: `build-changelog.mjs` and its tests |
| `.changeset/` | Pending release notes |

## Rules of the game client

- **Combat lockdown.** Protected frames cannot be shown, moved, bound, or have
  attributes changed by insecure code in combat. Anything that must work in
  combat runs as a secure snippet (`SecureHandlerWrapScript`, `_onshow`, and
  similar) with only restricted-environment APIs. Settings changes go through
  `ns.ApplyWhenSafe()`, which defers until `PLAYER_REGEN_ENABLED`.
- **Secret values.** Cooldowns, counts, and tooltip text can be secret in
  restricted content. Pass them to widgets inside `pcall`; never compare or do
  math on them.
- **Mirrored logic.** `PICK_DIRECTION` in `Wheel.lua` (restricted) must match
  `ns.DirectionIndex` in `Core.lua`. `spec/direction_spec.lua` enforces it.
- **Verify APIs** against the Forever UI source
  (`Gethe/wow-ui-source`, branch `forever`) before using them. Retail and
  Classic Era docs do not always apply.
- **Licenses.** Do not copy code from addons that are not permissively
  licensed, or from Blizzard UI source.

## Checks

```sh
npm ci
luacheck .            # lint (Lua 5.1)
busted                # unit tests
npm run test:scripts  # changelog generator tests
npm run changelog:check
```

Install busted and luacheck with LuaRocks against Lua 5.1 or LuaJIT, for
example `luarocks --lua-version 5.1 --lua-dir "$(brew --prefix luajit)" install --local busted`.
CI (`.github/workflows/ci.yml`) runs all of the above on every pull request
and push to `main`.

In-game verification is manual: symlink the repository to
`_forever_/Interface/AddOns/RadialBars` and `/reload`. Say clearly when a
change has not been tested in game.

## Changes and releases

- Work on a branch and open a pull request into `main`.
- Every user-visible change adds a changeset: `npx changeset` (or a file in
  `.changeset/`). Write it for players. CI fails a pull request without one.
- Do not edit `CHANGELOG.md`, `Changelog.lua`, or the `package.json` version
  by hand. Merging to `main` makes the release workflow open a
  "Version Packages" pull request that updates them; merging that pull
  request tags `v<version>` and runs the BigWigs packager, which publishes a
  GitHub release and uploads to CurseForge.
- CurseForge upload needs the `CF_API_TOKEN` repository secret and
  `## X-Curse-Project-ID` in the TOC. Never commit tokens.

## Style

- Tabs for indentation in Lua.
- Comments only where the reason is not obvious from the code.
- Commit messages: Conventional Commits (`feat:`, `fix:`, `chore:`, `ci:`,
  `docs:`, `test:`).

## Agent delivery policy

### Authority

- Humans own product and architecture decisions, scope, and exceptions.
- The main development agent is an orchestrator only: clarify decisions,
  scope and prioritize work, dispatch bounded assignments, reconcile
  dependencies and ownership, and accept verified results.
- The orchestrator may independently inspect live state and verify results,
  but must delegate all code, tests, fixes, documentation implementation,
  delivery pull request creation, review remediation, and shepherding.
- The [README](README.md) and existing upstream documentation remain the
  authority for addon usage, development, build, and release procedures.

### Delegated delivery

- Give each writing worker an owned, isolated worktree, explicit scope,
  acceptance criteria, validation requirements, and a return owner.
  Never share mutable checkouts or implement in the default checkout.
- Workers own their assigned implementation and focused validation. Delivery
  workers own publication, keeping their branch and checks current, review
  responses, and scope completion. Delivery requires independent review.
- Keep one delivery/shepherd owner per pull request. Bounded workers return
  evidence to that owner; they do not assume publication or shepherding duties.
- Bounded workers report actual changes, validation, remaining duties, and
  blockers to the delivery/shepherd owner; delivery workers report them to the
  orchestrator. A sent report is not an accepted handoff; acknowledge custody
  before transferring responsibility, without overlapping writers or monitors.
- Preserve unrelated work and other owners' scopes. Clean up only finished,
  owned resources after verifying work is preserved.

### Merge and identity boundaries

- PR Sniper runs separately with merge authority. Respect human authority and
  Sniper's existing scope; do not approve, merge, enable auto-merge on its behalf,
  or spawn a replacement Sniper.
- Claim communication, acceptance, or handoff only when observed.
- Use the configured personal Git and GitHub identity for this repository.
  Do not switch active accounts, change global credentials, or fall back to a
  work identity; escalate missing identity setup.
- Keep machine details, account data, and transient runtime state out of
  permanent documentation.

### Versioning

- Feature changes increment minor.
- Bug fixes increment revision (patch in `major.minor.patch`).
- Only the human/operator may increment major; agents and automation must not
  autonomously choose a major bump.
