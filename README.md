# Radial Bars

Radial action bars for World of Warcraft: Forever.

Current state: registers a **Radial Bars** page under
Options > AddOns that shows "Hello, World!". `/radialbars` opens it.

## Develop

Symlink this repository into the Forever AddOns folder (macOS):

```sh
ln -s ~/git/_opensource/jdylanmc/radial-bars \
  "/Applications/World of Warcraft/_forever_/Interface/AddOns/RadialBars"
```

The link must be named `RadialBars` to match `RadialBars.toc`. `/reload` in
game picks up new files and changes; renaming or deleting the TOC needs a
client restart.
