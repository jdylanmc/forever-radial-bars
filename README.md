# Radial Bars

Radial action bars for World of Warcraft: Forever.

Turns one action bar (2-8) into a circular wheel, opened by a hotkey at screen
center or at the mouse cursor. The original Blizzard bar stays visible; Action Bar 1 is not touched.

## Use

Open Options > AddOns > Radial Bars, or `/radialbars`. Every setting below is
saved per bar.

**Behavior**

- **Action bar:** which bar (2-8) the wheel shows.
- **Hotkey behavior:**
  - **Toggle:** press the hotkey to open, click a slot to use it. The wheel
    closes after use; the center **Cancel**, the hotkey again, or Esc closes it.
  - **Hold:** hold the hotkey and push the mouse toward a slot; it highlights
    and its name shows in the center. Release to use it. Releasing in the
    center **Cancel** zone uses nothing. The cursor is hidden while held and a
    pointer shows the direction (option: **Hide cursor in Hold mode**).
- **Open at:** screen center, the mouse cursor, or a fixed position. For a
  fixed position, click **Preview wheel** and drag the wheel into place.
- **Hotkey:** click, then press a key with optional Alt, Ctrl, Shift. It
  overrides any game binding on that key while Radial Bars is loaded.

**Appearance**

- **Icon shape:** Square (default, Blizzard action button border), Circle, or
  Radial slice (pie wedges; the whole wedge is clickable).
- **Sliders:** buttons shown (first 4-12 of the bar), icon size, spacing
  (distance from center), margin (backdrop around icons), center size (dead
  zone and slice hub), slice gap, backdrop opacity (0 hides it), icon opacity.
- **Show description in center:** the selected ability's name always shows in
  the center; its description shows too when the center is at least about 100
  pixels wide (raise **Center size** or **Spacing**).
- **Preview wheel** shows changes live.

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
| `Media/*.tga` | Generated textures: slices for 4-12 slots, pointer, blank cursor |

## Planned

More than one wheel at a time.
