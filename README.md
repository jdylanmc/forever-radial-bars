# Radial Bars

<img src="art/icon-400.png" alt="Radial Bars icon" width="160">

Radial action bars for World of Warcraft: Forever.

Gives each action bar (1-8) its own circular wheel and hotkey, opened at screen
center, the mouse cursor, or a fixed position. Only one wheel opens at a time:
opening another closes the previous wheel first. Original Blizzard bars,
their actions, and native bindings remain unchanged apart from temporary hotkey
overrides.

Bar 1 always uses fixed action slots 1-12, not the current stance, form, or
action page. It starts unbound.

## Use

Open Options > AddOns > Radial Bars, or `/radialbars`. Every setting below is
saved per bar.
Scroll within the settings panel to reach all controls when the window is short.

Settings are grouped into five sections:

**Action bar**

- Choose which bar (1-8) to **edit**. Other bars keep their settings and working
  hotkeys; selection does not deactivate them.
- **Copy settings from:** select a source bar, then click **Copy settings**.
  Copies all appearance, behavior, and placement settings to the edited bar,
  but keeps its hotkey (including unbound) and its own actions. The source
  stays unchanged. Copying a bar to itself is disabled.

**Activation**

- **Hotkey:** click, then press a key with optional Alt, Ctrl, Shift. It
  overrides any game binding on that key while Radial Bars is loaded.
  **Clear** removes that wheel's override, restoring the original game binding.
  Assigning a key already used by another radial bar moves it to the edited
  bar automatically; the previous bar keeps every other setting.
  Upgrades retain saved bar settings. If legacy bars shared a key, the previously
  selected bar keeps it; otherwise the lowest-numbered bar keeps it.
- **Hotkey behavior:**
  - **Toggle:** press the hotkey to open, click a slot to use it. The wheel
    closes after use; the center **Cancel**, the hotkey again, or Esc closes it.
  - **Hold:** hold the hotkey and push the mouse toward a slot; it highlights
    and its name shows in the center. Release to use it. Releasing in the
    center **Cancel** zone uses nothing.
    Switching wheels or cancelling invalidates the old held press: releasing
    it cannot use an action, even after reopening from a macro.
- **Hide cursor in Hold mode:** hides the cursor while held; a pointer shows
  the direction instead. Hiding covers the whole viewport, including outside
  the wheel, and ends when the wheel closes. Previews and Toggle mode keep
  their normal cursor.

**Placement**

- **Open at:** screen center, the mouse cursor, or a fixed position. For a
  fixed position, click **Preview wheel** and drag the wheel into place.
- **Preview wheel:** opens the floating wheel and shows changes live.
- **Live preview:** the embedded wheel shows the bar being edited, including
  empty slots. Hover to highlight a slot and inspect its name and optional
  description. Clicking never uses an action. It fits within the settings panel
  and reflects saved edits immediately, even while combat delays changes to
  the real wheel. Use the separate **Preview wheel** button to place a fixed wheel.

**Wheel layout**

- **Icon shape:** Square (default, Blizzard action button border), Circle, or
  Radial slice (pie wedges; the whole wedge is clickable).
- **Sliders:** buttons shown (first 4-12 of the bar), icon size, spacing
  (distance from center), margin (backdrop around icons), center size (dead
  zone and slice hub), slice gap, slice icon zoom.
- **Slice icon zoom:** Radial slice artwork fills its pie wedge. Zoom enlarges
  the artwork within that fixed wedge (default 115%, range 100-200%); the
  sides, circular rim, and center Cancel zone clip it. The control is disabled
  for Circle and Square; their icons are unchanged. Slice gaps remain visible
  over the artwork.

**Visibility**

- **Backdrop opacity:** 0 hides the backdrop.
- **Icon opacity:** how opaque the ability artwork appears.
- **Show description in center:** the selected ability's name always shows in
  the center; its description shows too when the center is at least about 100
  pixels wide (raise **Center size** or **Spacing**).

The real wheel works in combat. Settings changed in combat apply to it when
combat ends.

Options > AddOns > Radial Bars > **Changelog** lists what changed in each
version.

### Open from a macro

Put this line in a macro and place it on an action bar:

```text
/click RadialBarsOpen
```

With Radial Bars loaded, this opens the bar selected for editing. Repeating
it leaves an open wheel open, without moving it or using a slot. Click a slot
to use it, or use the center **Cancel** or Esc to close. The macro does not
simulate the hotkey: even in Hold mode, releasing the macro key uses nothing.
Hold-mode highlighting and cursor settings still apply.

The endpoint uses a secure click handler, so it is designed for macros used
in or out of combat; this path still needs in-game verification on Forever.
It does not select another bar or apply settings deferred until combat ends.
Bare `/radialbars` still opens settings.

## Develop

Symlink this repository into the Forever AddOns folder (macOS):

```sh
ln -s ~/git/_opensource/jdylanmc/forever-radial-bars \
  "/Applications/World of Warcraft/_forever_/Interface/AddOns/RadialBars"
```

The link must be named `RadialBars` to match `RadialBars.toc`. `/reload` in
game picks up new files and changes; renaming or deleting the TOC needs a
client restart.

See [AGENTS.md](AGENTS.md) for the file layout, client rules (combat
lockdown, secret values), and checks.

```sh
npm ci
luacheck .
busted
npm run test:scripts
npm run changelog:check
```

| File | Role |
| --- | --- |
| `Core.lua` | Saved settings, bar-to-slot map, combat-safe apply |
| `Wheel.lua` | Secure wheel, slot buttons, hotkey trigger, visuals |
| `Visuals.lua` | Shared icon geometry, native slice masks, read-only action labels |
| `SettingsPreview.lua` | Unprotected, hover-only embedded settings wheel |
| `Settings.lua` | Options page and key capture |
| `Media/*.tga`, `Media/Blank.blp` | Slice, hub, pointer and icon textures; transparent hardware cursor |
| `art/` | Icon source art, CurseForge avatar, hub-mask generator (not packaged) |

Slice artwork uses native `MaskTexture` objects: the existing wedge alpha
textures clip the sides and outer rim; `SliceHubMask.tga` cuts out the center.
Zoom changes only the artwork rectangle, not those masks or the hit target.
The selector accepts the full circular wedge outside the Cancel zone, not
the corners of the wheel's rectangular frame. Hold mode still selects by
direction even beyond the rim.

The mask APIs are documented in the
[Forever 1.60.1 (70959) client source](https://github.com/Gethe/wow-ui-source/tree/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_APIDocumentationGenerated).
Regenerate the inverse hub asset with `python art/generate-hub-mask.py`.
Regenerate the uncompressed hardware cursor with `python art/generate-blank-cursor.py`.
Rendering-call and texture-alpha tests do not replace an in-game visual check.

### Manual acceptance

The Lua tests execute a restricted-snippet behavioral model, not the game
engine's combat authorization. In-game verification is still required on
Forever, including:

- Bind all eight bars; switch between Hold and Toggle wheels during combat.
  Check only one wheel is visible and the previous wheel closes first.
- Hold A, open B, then release A; cancel with Esc or the center, reopen by
  macro, then release the old key. No stale release may use an action.
- Check Hold execution on release with both game key-down settings, cursor
  hiding/restoration, each positioning mode, and fixed bar 1 slots while
  changing stance, form, and action page.
- With Hide cursor enabled in Hold mode, move inside and outside the wheel,
  including viewport edges on ultrawide displays. Check no black square or
  cursor appears, world clicks and camera buttons still work, and closing or
  switching restores the appropriate cursor.
- Clear or move a radial key; verify the original game binding returns.
  Reload legacy fixture settings and check key ownership and bar settings.
- Edit and copy settings during combat; the inline preview updates immediately,
  the protected wheels update afterward, and neither preview uses actions.

Secure coordination uses restricted frame operations verified against the
[pinned Forever source](https://github.com/Gethe/wow-ui-source/tree/734f065329cff4992835b01a84f210a297db91b6):
`RestrictedFrames.lua` (`Show`/`Hide`, `SetAttribute`, `ClearBindings`,
`SetBindingClick`, `RunAttribute`) and `SecureTemplates.lua`
(`SecureActionButton_OnClick`). Source compatibility does not replace these
operator checks.

## Release

Releases are automated with [Changesets](https://github.com/changesets/changesets):

1. Each pull request adds a changeset (`npx changeset`) describing the change
   for players. CI requires one.
2. Merging to `main` opens or updates a **Version Packages** pull request that
   bumps the version and writes `CHANGELOG.md` and `Changelog.lua`.
3. Merging that pull request tags `v<version>` and runs the
   [BigWigs packager](https://github.com/BigWigsMods/packager), which publishes
   a GitHub release and uploads to CurseForge.

If packaging fails after the tag is pushed, re-run the **Release** workflow on
`main`. It packages an existing `v<version>` tag that has no GitHub release.
It also retries a release without an uploaded, nonempty ZIP asset; release
metadata alone does not mean packaging finished. The packager creates or
updates the GitHub release before uploading its ZIP. A re-run may upload the
same version to CurseForge again.

CurseForge upload needs the `CF_API_TOKEN` repository secret and
`## X-Curse-Project-ID` in `RadialBars.toc`.

## License

MIT. See [LICENSE](LICENSE).
