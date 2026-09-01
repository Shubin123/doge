# Atlas pipeline tests

Tests the sprite atlas pipeline (`../tools/`) stage by stage, running
against real sprites in `../src/gfx/` (not a separate copy of fixtures —
this way the tests always reflect the actual current assets).

## Setup

```sh
pip install pillow numpy pytest
# a real Lua interpreter, used to cross-validate the pixel-index and UV
# math against the original algorithm (not just against itself):
sudo apt-get install lua5.4   # or: brew install lua
```

## Run

```sh
pytest tests/            # everything
pytest tests/ -k stage1  # just one stage
pytest tests/ -s         # see the printed PSNR/size numbers
```

`tests/artifacts/` fills up with visual diff images (`stage3_*.png` —
original / decoded / diff-heatmap side by side) each run; safe to delete,
regenerated every time.

## What each stage checks

| File | Stage | How |
|---|---|---|
| `test_stage1_extraction.py` | source sheet -> uniform tiles | vectorized implementation vs. a deliberately slow, naive Python transliteration of the same nested loops (proves vectorization didn't change behavior); the pixel-index formula itself vs. a real Lua 5.4 interpreter running the original formula |
| `test_stage2_packing.py` | tiles -> packed atlas | crop every frame back out of the atlas and check it's byte-identical to what went in (lossless); UV-rect formula vs. real Lua running `calculateFrameOffsetsFromMetadata`'s math |
| `test_stage3_bc3_encode.py` | atlas -> BC3/DXT5 | lossy by design, so this is a quality gate: decode what the encoder produced, check PSNR / max error on *visible* pixels (alpha-aware — see the module docstring for why raw RGB error on transparent padding doesn't matter), and save contact-sheet PNGs (original / decoded / diff heatmap) for visual review. Includes a regression test for the alpha-dilation fix. |
| `test_stage4_zlib.py` | .dds -> .dds.zlib | lossless, so a plain bit-exact round-trip, plus a check that the stream is standard RFC1950 zlib (what `love.data.decompress` expects) |
| `test_end_to_end_cli.py` | the whole `pack_atlas.py` CLI | runs it as a subprocess end to end, decodes the result, and validates the metadata loads in real Lua with self-consistent indices |

A full production-scale run (25 sources, ~6800 sprites, 16384x16384
atlas) was validated manually while building this — see the delivery
notes — but isn't part of the routine suite since it needs ~2GB+ RAM and
~100s; the routine tests use a handful of real sprites, not the whole
roster, to stay fast.
