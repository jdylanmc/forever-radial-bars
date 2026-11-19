# Radial Bars

Radial action bars for World of Warcraft: Forever.

Turns one action bar (2-8) into a circular wheel at screen center, opened by a
hotkey. The original Blizzard bar stays visible; Action Bar 1 is not touched.

## Use

Open Options > AddOns > Radial Bars, or `/radialbars`:

- **Action bar:** which bar (2-8) the wheel shows.
- **Hotkey behavior** (per bar):
  - **Toggle:** press the hotkey to open, click a slot to use it. The wheel
    closes after use; the hotkey again or Esc closes it.
  - **Hold:** hold the hotkey, move the cursor over a slot, release to use it.
- **Hotkey** (per bar): click, then press a key with optional Alt, Ctrl, Shift.
  It overrides any game binding on that key while Radial Bars is loaded.

Works in combat. Settings changed in combat apply when combat ends.

## Develop

Symlink this repository into the Forever AddOns folder (macOS):

```sh
ln -s ~/git/_opensource/jdylanmc/radial-bars \
  "/Applications/World of Warcraft/_forever_/Interface/AddOns/RadialBars"
```

The link must be named `RadialBars` to match `RadialBars.toc`. `/reload` in
game picks up new files and changes; renaming or deleting the TOC needs a
client restart.

| File | Role |
| --- | --- |
| `Core.lua` | Saved settings, bar-to-slot map, combat-safe apply |
| `Wheel.lua` | Secure wheel, slot buttons, hotkey trigger, visuals |
| `Settings.lua` | Options page and key capture |

## Planned

Moving the wheel, opening at the cursor, more than one wheel at a time.
Per-bar settings already store a `position` field for this.
