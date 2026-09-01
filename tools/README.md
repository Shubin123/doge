# Sprite atlas pipeline

One command, source sprite sheets in, a ready-to-load compressed atlas out:

```sh
python3 tools/pack_atlas.py \
  --config configs/production_atlas.json \
  --gfx-root src \
  --out-atlas src/gfx/atlas/atla.dds.zlib \
  --out-metadata src/gfx/atlas/atlas_metadata.lua
```

Then in Lua:

```lua
gun_enemies = characterAnimator.loadFromAtlas("gfx/atlas/atla.dds.zlib", "gfx/atlas/atlas_metadata.lua", true)
```

This replaces what used to be four separate manual steps: build the atlas
by uncommenting a `characterAnimator.createAndSaveAtlas(...)` call in
`main.lua` and running the game once, compile and run `bc-encoder` by hand
on the resulting PNG, run `misc/compress.lua` inside LÖVE by hand to zlib
it, then hand-edit `main.lua` and the metadata's `characterDefinitions`
table (by sprite index!) to match. Now it's one call, and `bc-encoder` gets
compiled automatically the first time it's needed.

## Requirements

- Python 3.9+, with `pillow` and `numpy` (`pip install pillow numpy`)
- `gcc` (to build `bc-encoder/` — done automatically on first run; an
  OpenMP-capable `gcc` is used if available, which matters a lot on a
  production-size 8k-16k atlas)

## Config format

A JSON file listing every source sheet and, optionally, the character ->
animation -> sprite mapping (`configs/production_atlas.json` is a real,
working example):

```json
{
  "uniformWidth": 128,
  "uniformHeight": 128,
  "sources": [
    { "path": "gfx/testCharacter/walk.png", "directions": 2,
      "frameWidth": 64, "frameHeight": 128 }
  ],
  "characterDefinitions": {
    "someCharacter": {
      "animations": { "walk": "gfx/testCharacter/walk.png" },
      "defaultAnimation": "walk"
    }
  }
}
```

- `sources[].path` is relative to `--gfx-root` (pass `--gfx-root src` so
  paths read the same as they do inside the game's Lua, e.g.
  `gfx/watchmanOfDoom_lowres/idle.png`). Every path is checked to exist
  *before* any work starts — a typo fails immediately with a clear error
  instead of partway through a multi-minute build.
- `directions` is how many columns the sheet is laid out in (this is
  the old `config[i]` parameter to `createAndSaveAtlas` — for an
  8-directional character sheet that's 8; for a single-column strip of
  frames, or a single static sprite, that's 1). Rows below the first are
  additional frames.
- `characterDefinitions[...].animations[...]` reference sources **by
  path**, not by numeric sprite index. The old hand-written metadata
  hardcoded indices (`["walk"] = 12`) that a human had to keep in sync by
  hand whenever the source list changed order or length — the pipeline
  resolves the index automatically now, and validates every reference
  points at a source that's actually in the config.
- A source's sheet can come from anywhere — Unity's grid export, Aseprite,
  a hand-drawn sheet — the config only needs to know its path and column
  count. "Gathering" one sprite for an object is just adding an entry
  here, not a code change.

## What the pipeline does, in order

1. **Extract** — slice every source sheet into uniform 128x128 tiles
   (nearest-neighbor resample, same math the old Lua `createAndSaveAtlas`
   used — see `atlas_lib.extract_frames_from_source`).
2. **Pack** — lay every tile into one square power-of-two atlas texture,
   row-major (`atlas_lib.pack_atlas`), with alpha-padding dilation so
   transparent padding pixels don't drag BC3's shared per-block color
   line toward black and fringe visible sprite edges
   (`atlas_lib.dilate_alpha_padding` — this is a real fix, not just a
   test threshold; see `tests/test_stage3_bc3_encode.py`).
3. **Encode** — BC3/DXT5-compress the atlas via the `bc-encoder` C tool
   (`encode_lib.encode_rgba_to_dds_bytes`), auto-built (with OpenMP if
   available) the first time it's needed.
4. **Compress** — zlib-frame the `.dds` bytes
   (`encode_lib.zlib_compress`), the same format `love.data.decompress`
   expects.

All in memory between steps — nothing is written to disk except the final
`.dds.zlib` and `_metadata.lua` (pass `--dump-atlas-png` to also get the
uncompressed atlas as a PNG for visual inspection).

## Useful flags

- `--no-compress` — stop after BC3 encoding, write a raw `.dds` (skip the
  zlib step; pass `false` for the third argument to `loadFromAtlas` then).
- `--no-dilate` — skip the alpha-padding fix (not recommended).
- `--dilate-iterations N` — default 4; how many pixels deep to bleed
  visible color into transparent padding.
- `--dump-atlas-png path.png` — also write the uncompressed RGBA atlas,
  for a visual before/after check.

## Tests

`../tests/` has the pipeline's own test suite — bit-exact checks on the
lossless stages (extraction, packing, zlib) cross-validated against a real
Lua 5.4 interpreter running transliterations of the original algorithm,
and PSNR/visual-diff checks on the lossy BC3 stage — all run against real
sprites already in `src/gfx/`, not synthetic fixtures. See
`../tests/README.md`.
