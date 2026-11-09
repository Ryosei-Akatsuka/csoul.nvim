# csoul

A quiet little colorscheme studio for Neovim — first as a static terminal UI study.

This repository is the design step before the Neovim implementation: a
dependency-free Python script paints the finished picker with ANSI truecolor so
the composition, palette, typography and spacing can be judged in a real
terminal.

```text
                                                    32 detected · nvim 0.12.5
    / Search schemes, palettes, moods...                ALL 32   DARK 26   LIGHT 6
    Schemes  15 / 32                                    Preview
    01 kanagawa-wave    󱓻󱓻󱓻󱓻󱓻󱓻󱓻󱓻󱓻󱓻 current          kanagawa-wave
```

## Run

The study is composed for **112 × 33 cells** and truecolor. The color chips
beside each scheme name use the Nerd Font glyph `󱓻` (`nf-md-square_rounded`),
so run it with a Nerd Font-patched terminal font.

```sh
python3 preview.py
```

Or, on this Nix machine:

```sh
nix run .
nix develop          # python3 + neovim + git
```

## What it discovers

The script asks the local Neovim for its `runtimepath`, then scans:

- Neovim's own `runtime/colors`
- `~/.config/nvim/colors`
- lazy.nvim plugins (`~/.local/share/nvim/lazy/*/colors`)
- `pack/*/start/*` and `pack/*/opt/*`
- `plugged` and the usual XDG locations

It reports the real number of detected schemes, splits them into dark/light,
and shows where the selected scheme comes from (`nvim runtime`, a plugin, user
colors, or a curated fallback).

The static composition previews **Kanagawa Wave** when it is available, with a
curated fallback when it is not. The palette library in `preview.py` includes
the palettes used by the list; the active preview above uses Kanagawa Wave's
real highlight colours.

## Design notes

- Only elements that carry information or speed up choosing are drawn: search,
  filters, the scheme list with ten colour chips per row, key hints, the palette,
  a syntax sample, and UI chips (`Normal`, `Visual`, `Search`, `Error`, `Hint`).
- The selected row is a low-contrast wash with a solid accent spine.
- No frame, shadow, backdrop, gradients, dividers, or decorative letterspacing.
- Truecolor only; no third-party Python packages.
