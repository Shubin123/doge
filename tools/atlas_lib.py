"""
atlas_lib.py — core, dependency-light logic for the one-step sprite atlas
encoder pipeline.

This module owns exactly two lossless stages of the pipeline:

  1. extract_frames_from_source()  — slice a source spritesheet (however it
     was produced: a Unity grid export, an Aseprite export, a hand-drawn
     sheet, ...) into NxM "uniform" tiles, using the *same* nearest-neighbor
     clamped-sampling rule the old Lua implementation
     (characterAnimator.createAndSaveAtlas in src/game/characterAnimator.lua)
     used. This is deliberately bit-for-bit compatible so re-running the
     pipeline on unchanged sources reproduces unchanged pixels.

  2. pack_atlas()                  — place uniform tiles into a single
     power-of-two atlas texture, using the same row-major layout math as
     calculateFrameOffsetsFromMetadata() in characterAnimator.lua, so the
     UV math the game already has does not need to change.

Both stages operate purely in memory (numpy arrays) — no intermediate files
are written unless the caller asks for them. BC3 encoding and zlib framing
live in encode_lib.py; the two are combined by pack_atlas.py so
the whole "stitch + encode" process is a single call/command.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Optional

import numpy as np
from PIL import Image

UNIFORM_WIDTH = 128
UNIFORM_HEIGHT = 128


@dataclass
class SourceSpec:
    """One entry of the atlas config: a single sprite source and how many
    'directions' (columns) it is laid out in, mirroring the old
    (imageFiles[i], config[i]) pair passed to createAndSaveAtlas."""
    path: str          # repo-relative path, e.g. "gfx/testCharacter/walk.png"
    directions: int = 1
    frame_width: Optional[int] = None
    frame_height: Optional[int] = None


@dataclass
class PackedAtlas:
    image: np.ndarray                 # HxWx4 uint8 RGBA
    frames_per_image: list[int] = field(default_factory=list)
    directions_per_image: list[int] = field(default_factory=list)
    image_files: list[str] = field(default_factory=list)
    sprites_per_row: int = 0
    uniform_width: int = UNIFORM_WIDTH
    uniform_height: int = UNIFORM_HEIGHT
    total_sprites: int = 0

    @property
    def texture_width(self) -> int:
        return self.image.shape[1]

    @property
    def texture_height(self) -> int:
        return self.image.shape[0]


def load_rgba(path: str) -> np.ndarray:
    """Load an image as an HxWx4 uint8 RGBA numpy array."""
    with Image.open(path) as im:
        im = im.convert("RGBA")
        return np.array(im, dtype=np.uint8)


def _nearest_index_map(dst_len: int, src_len: int, src_start: int, src_extent: int) -> np.ndarray:
    """Reproduces, vectorized, the per-axis math from the Lua source:

        srcX = math.floor(x * spriteWidth / uniformWidth)
        srcX = srcXStart + math.max(0, math.min(srcX, spriteWidth - 1))

    (same shape for Y). Returns an array of length dst_len with the source
    index for each destination pixel along one axis.
    """
    x = np.arange(dst_len, dtype=np.int64)
    idx = (x * src_extent) // dst_len  # floor division, matches math.floor for non-negative ints
    idx = np.clip(idx, 0, src_extent - 1)
    return src_start + idx


def extract_frames_from_source(
    spec: SourceSpec,
    uniform_width: int = UNIFORM_WIDTH,
    uniform_height: int = UNIFORM_HEIGHT,
) -> list[np.ndarray]:
    """Slice one source sheet into uniform-size RGBA tiles.

    Matches characterAnimator.createAndSaveAtlas's first pass exactly:
    the sheet is treated as a `directions`-column grid, each cell's height
    is `frame_height` (or square to width if unspecified), rows below that
    are additional frames, and every cell is nearest-neighbor resampled
    (with edge clamping) into a uniform_width x uniform_height tile.
    Pixels the source doesn't cover (partial cells) come out transparent.
    """
    img = load_rgba(spec.path)
    src_h, src_w = img.shape[0], img.shape[1]

    directions = spec.directions
    sprite_width = spec.frame_width or (src_w // directions)
    sprite_height = spec.frame_height or sprite_width

    sprites_x = directions
    sprites_y = src_h // sprite_height

    col_idx = _nearest_index_map(uniform_width, uniform_width, 0, sprite_width)
    row_idx = _nearest_index_map(uniform_height, uniform_height, 0, sprite_height)

    tiles: list[np.ndarray] = []
    for sy in range(sprites_y):
        for sx in range(sprites_x):
            src_x_start = sx * sprite_width
            src_y_start = sy * sprite_height

            abs_cols = src_x_start + col_idx
            abs_rows = src_y_start + row_idx

            tile = np.zeros((uniform_height, uniform_width, 4), dtype=np.uint8)

            col_in_bounds = abs_cols < src_w
            row_in_bounds = abs_rows < src_h
            if col_in_bounds.all() and row_in_bounds.all():
                tile[:, :, :] = img[np.ix_(abs_rows, abs_cols)]
            else:
                valid_cols = np.where(col_in_bounds)[0]
                valid_rows = np.where(row_in_bounds)[0]
                if len(valid_cols) and len(valid_rows):
                    sub = img[np.ix_(abs_rows[valid_rows], abs_cols[valid_cols])]
                    tile[np.ix_(valid_rows, valid_cols)] = sub

            tiles.append(tile)
    return tiles


def next_power_of_two(n: int) -> int:
    if n <= 1:
        return 1
    return 1 << (n - 1).bit_length()


def pack_atlas(
    sources: list[SourceSpec],
    uniform_width: int = UNIFORM_WIDTH,
    uniform_height: int = UNIFORM_HEIGHT,
    dilate: bool = False,
    dilate_iterations: int = 4,
) -> PackedAtlas:
    """Stage 1 + Stage 2 combined: extract every source's frames and pack
    them into one square power-of-two atlas, row-major, exactly matching
    calculateFrameOffsetsFromMetadata()'s UV assumptions on the Lua side.

    When `dilate` is set, each tile has dilate_alpha_padding() applied
    *before* packing, one 128x128 tile at a time rather than on the whole
    atlas afterwards. That's not just faster — on a full production-size
    atlas (16384x16384, mostly empty grid cells) a whole-canvas dilation
    pass allocates several float32 copies of the entire texture at once,
    which is enough to get OOM-killed. Since sprite tiles are always
    packed on a uniform_width/height-aligned grid and BC3 blocks are 4x4,
    no BC3 block ever straddles a tile boundary anyway, so per-tile
    dilation is both cheaper and the semantically correct scope (it never
    needs to know about neighboring sprites).
    """
    all_tiles: list[np.ndarray] = []
    frames_per_image: list[int] = []
    directions_per_image: list[int] = []
    image_files: list[str] = []

    for spec in sources:
        tiles = extract_frames_from_source(spec, uniform_width, uniform_height)
        if dilate:
            tiles = [dilate_alpha_padding(t, iterations=dilate_iterations) for t in tiles]
        all_tiles.extend(tiles)
        frames_per_image.append(len(tiles))
        directions_per_image.append(spec.directions)
        image_files.append(spec.path)

    total_sprites = len(all_tiles)
    sprites_per_row = math.ceil(math.sqrt(total_sprites)) if total_sprites else 1
    texture_width = next_power_of_two(sprites_per_row * uniform_width)
    texture_height = next_power_of_two(sprites_per_row * uniform_height)
    # after power-of-two rounding, recompute sprites-per-row exactly as the
    # Lua code does (floor(textureWidth / uniformWidth))
    sprites_per_row = texture_width // uniform_width

    atlas = np.zeros((texture_height, texture_width, 4), dtype=np.uint8)
    for i, tile in enumerate(all_tiles):
        row = i // sprites_per_row
        col = i % sprites_per_row
        dest_y = row * uniform_height
        dest_x = col * uniform_width
        if dest_y + uniform_height <= texture_height and dest_x + uniform_width <= texture_width:
            atlas[dest_y:dest_y + uniform_height, dest_x:dest_x + uniform_width] = tile

    return PackedAtlas(
        image=atlas,
        frames_per_image=frames_per_image,
        directions_per_image=directions_per_image,
        image_files=image_files,
        sprites_per_row=sprites_per_row,
        uniform_width=uniform_width,
        uniform_height=uniform_height,
        total_sprites=total_sprites,
    )


def dilate_alpha_padding(rgba: np.ndarray, iterations: int = 4) -> np.ndarray:
    """Bleed visible edge color into fully-transparent (alpha==0) padding.

    BC3/DXT5 shares one 2-endpoint color interpolation line across a whole
    4x4 block. Padding pixels stored as pure black (0,0,0,0) — which is
    what an empty atlas cell or an unused grid slot is — drag that shared
    line toward black, visibly darkening/discoloring genuinely-visible
    pixels in the same block near a sprite's silhouette edge. Since the
    alpha channel already makes those padding pixels invisible at draw
    time, giving them a color that matches their visible neighbors instead
    of black costs nothing and removes that fringe artifact. This never
    touches a pixel that already has alpha>0.
    """
    out = rgba.copy()
    rgb = out[:, :, :3].astype(np.float32)
    alpha = out[:, :, 3]
    known = alpha > 0

    for _ in range(iterations):
        unknown = ~known
        if not unknown.any():
            break
        sum_rgb = np.zeros_like(rgb)
        count = np.zeros(alpha.shape, dtype=np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                shifted_known = np.roll(np.roll(known, dy, axis=0), dx, axis=1)
                shifted_rgb = np.roll(np.roll(rgb, dy, axis=0), dx, axis=1)
                valid = shifted_known.copy()
                if dy == 1:
                    valid[0, :] = False
                elif dy == -1:
                    valid[-1, :] = False
                if dx == 1:
                    valid[:, 0] = False
                elif dx == -1:
                    valid[:, -1] = False
                sum_rgb += np.where(valid[..., None], shifted_rgb, 0)
                count += valid

        fillable = unknown & (count > 0)
        avg = np.divide(sum_rgb, count[..., None], out=np.zeros_like(sum_rgb), where=count[..., None] > 0)
        rgb = np.where(fillable[..., None], avg, rgb)
        known = known | fillable

    out[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    return out


def frame_uv_rect(packed: PackedAtlas, global_index: int) -> tuple[int, int, int, int]:
    """Pixel-space (x0, y0, x1, y1) rectangle for a given global frame index,
    mirroring the u/v math in calculateFrameOffsetsFromMetadata()."""
    row = global_index // packed.sprites_per_row
    col = global_index % packed.sprites_per_row
    x0 = col * packed.uniform_width
    y0 = row * packed.uniform_height
    return x0, y0, x0 + packed.uniform_width, y0 + packed.uniform_height


def crop_frame(packed: PackedAtlas, global_index: int) -> np.ndarray:
    x0, y0, x1, y1 = frame_uv_rect(packed, global_index)
    return packed.image[y0:y1, x0:x1]
