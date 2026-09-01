"""
Stage 1 tests: source sheet -> uniform tiles.

Two independent checks, since no LÖVE runtime is available in this
sandbox to run the original Lua code directly:

  1. `test_matches_slow_python_transliteration` — the fast, vectorized
     `atlas_lib.extract_frames_from_source` is checked pixel-for-pixel
     against `_slow_reference_extract`, a deliberately naive nested-loop
     Python transliteration of the Lua algorithm (same variable names,
     same order of operations) for every real fixture image. This proves
     the vectorization didn't change behavior.

  2. `test_index_math_matches_real_lua` — the per-axis nearest-neighbor
     index formula (`atlas_lib._nearest_index_map`) is checked against
     `tests/lua_ref/index_map.lua` executed by a *real* Lua 5.4
     interpreter, for a range of uniform/sprite dimensions. This is the
     one part of stage 1 that's pure arithmetic (no love.image needed),
     so it can be validated bit-for-bit cross-language.
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


def _slow_reference_extract(spec: atlas_lib.SourceSpec, uniform_width: int, uniform_height: int):
    """Naive, unvectorized transliteration of the Lua nested loops in
    characterAnimator.createAndSaveAtlas. Intentionally slow and dumb —
    it exists only as an independent oracle for the fast implementation."""
    img = atlas_lib.load_rgba(spec.path)
    src_h, src_w = img.shape[0], img.shape[1]

    directions = spec.directions
    sprite_width = spec.frame_width or (src_w // directions)
    sprite_height = spec.frame_height or sprite_width

    sprites_x = directions
    sprites_y = src_h // sprite_height

    tiles = []
    for sy in range(sprites_y):
        for sx in range(sprites_x):
            src_x_start = sx * sprite_width
            src_y_start = sy * sprite_height
            tile = np.zeros((uniform_height, uniform_width, 4), dtype=np.uint8)
            for y in range(uniform_height):
                for x in range(uniform_width):
                    src_x = (x * sprite_width) // uniform_width
                    src_y = (y * sprite_height) // uniform_height
                    src_x = src_x_start + max(0, min(src_x, sprite_width - 1))
                    src_y = src_y_start + max(0, min(src_y, sprite_height - 1))
                    if src_x < src_w and src_y < src_h:
                        tile[y, x] = img[src_y, src_x]
                    # else stays transparent (0,0,0,0)
            tiles.append(tile)
    return tiles


FIXTURE_SPECS = [
    # exact-fit, upsampled (52px cells magnified to the 128px uniform tile)
    atlas_lib.SourceSpec(str(FIXTURES / "DancingGirlSheets/hips.png"), directions=6, frame_width=52, frame_height=53),
    # exact-fit, another upsample ratio
    atlas_lib.SourceSpec(str(FIXTURES / "EnemiesSpriteSheets/enemy-01.png"), directions=5, frame_width=48, frame_height=48),
    # exact-fit, mixed (upsample x, exact y)
    atlas_lib.SourceSpec(str(FIXTURES / "testCharacter/idle.png"), directions=2, frame_width=64, frame_height=128),
    # exact-fit at native uniform size — mirrors real production config
    # (this file's frame count, 112, matches framesPerImageList[17] in the
    # shipped atlas_metadata3.lua exactly)
    atlas_lib.SourceSpec(str(FIXTURES / "watchmanOfDoom_lowres/idle.png"), directions=8, frame_width=128, frame_height=128),
    # deliberately overflows the source width (5*48=240 > 192px wide) to
    # exercise the transparent out-of-bounds clamp branch
    atlas_lib.SourceSpec(str(FIXTURES / "EnemiesSpriteSheets/enemy-02.png"), directions=5, frame_width=48, frame_height=48),
]


@pytest.mark.parametrize("spec", FIXTURE_SPECS, ids=lambda s: Path(s.path).name)
def test_matches_slow_python_transliteration(spec):
    fast = atlas_lib.extract_frames_from_source(spec, 128, 128)
    slow = _slow_reference_extract(spec, 128, 128)
    assert len(fast) == len(slow) and len(fast) > 0
    for i, (f, s) in enumerate(zip(fast, slow)):
        assert np.array_equal(f, s), f"frame {i} of {spec.path} mismatched between fast and slow paths"


@pytest.mark.parametrize(
    "uniform_dim,sprite_dim",
    [(128, 128), (128, 64), (128, 37), (64, 100), (128, 1), (32, 128)],
)
def test_index_math_matches_real_lua(uniform_dim, sprite_dim):
    lua_out = subprocess.run(
        ["lua5.4", str(LUA_REF / "index_map.lua"), str(uniform_dim), str(sprite_dim)],
        capture_output=True, text=True, check=True,
    ).stdout.strip().splitlines()
    lua_indices = [int(v) for v in lua_out]

    py_indices = atlas_lib._nearest_index_map(uniform_dim, uniform_dim, 0, sprite_dim).tolist()

    assert lua_indices == py_indices
