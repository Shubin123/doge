"""
Stage 2 tests: uniform tiles -> packed power-of-two atlas.

  1. `test_pack_roundtrip_is_lossless` — packs every fixture's frames into
     one atlas, then crops each frame back out at its computed UV rect and
     checks it is byte-identical to the tile that went in. This is the
     "does the atlas re-store what you put into it" bit-exact test.

  2. `test_uv_math_matches_real_lua` — the UV-rect formula
     (`atlas_lib.frame_uv_rect`, expressed as normalized u/v/uSize/vSize)
     is checked against `tests/lua_ref/uv_map.lua` executed by a real Lua
     5.4 interpreter — this is the exact formula
     calculateFrameOffsetsFromMetadata() uses at runtime to look up a
     sprite in the atlas, so if this matches, the game's shader UVs will
     land on the same texels our packer wrote them to.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

TOOLS = Path(__file__).resolve().parent.parent / "tools"
FIXTURES = Path(__file__).resolve().parent.parent / "src" / "gfx"
LUA_REF = Path(__file__).resolve().parent / "lua_ref"
sys.path.insert(0, str(TOOLS))

import atlas_lib  # noqa: E402


ALL_SPECS = [
    atlas_lib.SourceSpec(str(FIXTURES / "DancingGirlSheets/hips.png"), directions=6, frame_width=52, frame_height=53),
    atlas_lib.SourceSpec(str(FIXTURES / "DancingGirlSheets/skip.png"), directions=6, frame_width=52, frame_height=53),
    atlas_lib.SourceSpec(str(FIXTURES / "EnemiesSpriteSheets/enemy-01.png"), directions=5, frame_width=48, frame_height=48),
    atlas_lib.SourceSpec(str(FIXTURES / "EnemiesSpriteSheets/enemy-02.png"), directions=5, frame_width=48, frame_height=48),
    atlas_lib.SourceSpec(str(FIXTURES / "testCharacter/idle.png"), directions=2, frame_width=64, frame_height=128),
    atlas_lib.SourceSpec(str(FIXTURES / "testCharacter/walk.png"), directions=2, frame_width=64, frame_height=128),
    atlas_lib.SourceSpec(str(FIXTURES / "watchmanOfDoom_lowres/idle.png"), directions=8, frame_width=128, frame_height=128),
    atlas_lib.SourceSpec(str(FIXTURES / "watchmanOfDoom_lowres/walk.png"), directions=8, frame_width=128, frame_height=128),
]


@pytest.fixture(scope="module")
def packed():
    return atlas_lib.pack_atlas(ALL_SPECS, 128, 128)


def test_pack_roundtrip_is_lossless(packed):
    # rebuild the same flat tile list independently so we know what
    # *should* be at each global frame index
    expected_tiles = []
    for spec in ALL_SPECS:
        expected_tiles.extend(atlas_lib.extract_frames_from_source(spec, 128, 128))

    assert packed.total_sprites == len(expected_tiles)
    assert packed.total_sprites > 0

    for i, expected in enumerate(expected_tiles):
        actual = atlas_lib.crop_frame(packed, i)
        assert np.array_equal(actual, expected), f"global frame {i} does not round-trip through the atlas"


def test_pack_dimensions_are_power_of_two_and_square(packed):
    w, h = packed.texture_width, packed.texture_height
    assert w == h, "atlas should be square, like the Lua packer produces"
    assert (w & (w - 1)) == 0, "atlas width must be a power of two"
    assert packed.sprites_per_row * packed.uniform_width == w


def test_dilate_option_only_touches_transparent_padding():
    """pack_atlas(dilate=True) must never change a pixel that already had
    alpha>0 — dilation only fills in color for fully-transparent padding,
    per-tile, before packing (see atlas_lib.pack_atlas's docstring for why
    this has to happen per-tile instead of on the whole atlas)."""
    specs = [
        atlas_lib.SourceSpec(str(FIXTURES / "EnemiesSpriteSheets/enemy-01.png"), directions=5, frame_width=48, frame_height=48),
        atlas_lib.SourceSpec(str(FIXTURES / "watchmanOfDoom_lowres/idle.png"), directions=8, frame_width=128, frame_height=128),
    ]
    plain = atlas_lib.pack_atlas(specs, 128, 128, dilate=False)
    dilated = atlas_lib.pack_atlas(specs, 128, 128, dilate=True)

    assert plain.total_sprites == dilated.total_sprites
    visible = plain.image[:, :, 3] > 0
    assert np.array_equal(plain.image[visible], dilated.image[visible]), \
        "dilation changed a pixel that was already visible (alpha>0)"
    assert np.array_equal(plain.image[:, :, 3], dilated.image[:, :, 3]), \
        "dilation must never change the alpha channel, only RGB in padding"
    # and it should actually have changed *something* in the padding, or
    # this fixture set doesn't exercise the feature at all
    assert not np.array_equal(plain.image[~visible], dilated.image[~visible])


def test_uv_math_matches_real_lua(packed):
    lua_out = subprocess.run(
        [
            "lua5.4", str(LUA_REF / "uv_map.lua"),
            str(packed.sprites_per_row), str(packed.uniform_width), str(packed.uniform_height),
            str(packed.texture_width), str(packed.texture_height), str(packed.total_sprites),
        ],
        capture_output=True, text=True, check=True,
    ).stdout.strip().splitlines()

    for i, line in enumerate(lua_out):
        lu, lv, lus, lvs = (float(v) for v in line.split(","))
        x0, y0, x1, y1 = atlas_lib.frame_uv_rect(packed, i)
        pu = x0 / packed.texture_width
        pv = y0 / packed.texture_height
        pus = packed.uniform_width / packed.texture_width
        pvs = packed.uniform_height / packed.texture_height
        assert (lu, lv, lus, lvs) == (pu, pv, pus, pvs), f"UV mismatch at frame {i}"
