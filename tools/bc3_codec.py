"""
bc3_codec.py — a small, pure-Python/numpy BC3 (DXT5) *decoder*.

The pipeline's actual encoder stays the battle-tested C `bc-encoder` tool
(stb_dxt) — this module exists purely so the test suite can verify what
that encoder produced without needing a GPU or a full graphics runtime:
decode the DDS bytes back to RGBA and compare against the source atlas.

Only decoding is implemented (encoding stays in the C tool). The block
layout and interpolation formulas follow the standard BC3/DXT5 spec.
"""
from __future__ import annotations

import struct

import numpy as np

DDS_HEADER_SIZE = 128  # matches sizeof(DDS_HEADER) in bc-encoder/main.c


def read_dds_dimensions(data: bytes) -> tuple[int, int]:
    magic = data[0:4]
    if magic != b"DDS ":
        raise ValueError("not a DDS file (bad magic)")
    height, width = struct.unpack_from("<II", data, 12)
    return width, height


def _unpack_565(v: np.ndarray) -> np.ndarray:
    """v: (...,) uint16/uint32 array -> (...,3) uint8 RGB array."""
    r5 = (v >> 11) & 0x1F
    g6 = (v >> 5) & 0x3F
    b5 = v & 0x1F
    r8 = (r5 * 255) // 31
    g8 = (g6 * 255) // 63
    b8 = (b5 * 255) // 31
    return np.stack([r8, g8, b8], axis=-1).astype(np.uint8)


def decode_bc3(data: bytes, width: int, height: int, header_offset: int = DDS_HEADER_SIZE) -> np.ndarray:
    """Decode raw BC3/DXT5 block data into an (height, width, 4) uint8 RGBA array.

    Assumes width/height are multiples of 4 (true for every atlas this
    pipeline produces, since uniform tiles are 128x128 and the atlas is
    always packed as a power-of-two multiple of that).
    """
    if width % 4 or height % 4:
        raise ValueError("decode_bc3 only supports dimensions that are multiples of 4")

    blocks_x = width // 4
    blocks_y = height // 4
    n_blocks = blocks_x * blocks_y

    block_bytes = np.frombuffer(data, dtype=np.uint8, count=n_blocks * 16, offset=header_offset)
    blocks = block_bytes.reshape(n_blocks, 16)

    alpha0 = blocks[:, 0].astype(np.uint32)
    alpha1 = blocks[:, 1].astype(np.uint32)
    alpha_idx_bytes = blocks[:, 2:8]  # 6 bytes -> 48 bits -> 16 * 3-bit indices
    # unpack 48-bit little-endian value per block
    bits = np.zeros(n_blocks, dtype=np.uint64)
    for i in range(6):
        bits |= alpha_idx_bytes[:, i].astype(np.uint64) << np.uint64(8 * i)
    alpha_idx = np.stack([((bits >> np.uint64(3 * k)) & np.uint64(0x7)) for k in range(16)], axis=-1)  # (n,16)

    mode1 = alpha0 > alpha1  # 8-alpha interpolation mode

    def interp8(k):
        return (( (7 - k) * alpha0 + k * alpha1) // 7)

    def interp6(k):
        return (((5 - k) * alpha0 + k * alpha1) // 5)

    alpha_palette = np.zeros((n_blocks, 8), dtype=np.uint32)
    alpha_palette[:, 0] = alpha0
    alpha_palette[:, 1] = alpha1
    for k in range(2, 8):
        v8 = interp8(k - 1)
        v6 = interp6(k - 1) if k < 6 else None
        if k < 6:
            alpha_palette[:, k] = np.where(mode1, v8, v6)
        else:
            fallback = np.full(n_blocks, 0 if k == 6 else 255, dtype=np.uint32)
            alpha_palette[:, k] = np.where(mode1, v8, fallback)

    alpha_vals = np.take_along_axis(alpha_palette, alpha_idx.astype(np.int64), axis=1)  # (n,16)

    color0 = blocks[:, 8].astype(np.uint32) | (blocks[:, 9].astype(np.uint32) << 8)
    color1 = blocks[:, 10].astype(np.uint32) | (blocks[:, 11].astype(np.uint32) << 8)
    color_idx_bytes = blocks[:, 12:16]
    color_bits = (
        color_idx_bytes[:, 0].astype(np.uint32)
        | (color_idx_bytes[:, 1].astype(np.uint32) << 8)
        | (color_idx_bytes[:, 2].astype(np.uint32) << 16)
        | (color_idx_bytes[:, 3].astype(np.uint32) << 24)
    )
    color_idx = np.stack([((color_bits >> np.uint32(2 * k)) & np.uint32(0x3)) for k in range(16)], axis=-1)

    c0 = _unpack_565(color0).astype(np.uint32)  # (n,3)
    c1 = _unpack_565(color1).astype(np.uint32)
    c2 = (2 * c0 + c1 + 1) // 3
    c3 = (c0 + 2 * c1 + 1) // 3
    color_palette = np.stack([c0, c1, c2, c3], axis=1)  # (n,4,3)

    rgb_vals = np.take_along_axis(
        color_palette, color_idx[:, :, None].astype(np.int64).repeat(3, axis=2), axis=1
    )  # (n,16,3)

    out = np.empty((n_blocks, 16, 4), dtype=np.uint8)
    out[:, :, :3] = rgb_vals.astype(np.uint8)
    out[:, :, 3] = alpha_vals.astype(np.uint8)

    # scatter blocks (row-major, block_idx = by*blocks_x + bx, matching
    # bc-encoder/main.c's compress_to_bc3) into the full image, vectorized
    # (no per-block Python loop — matters once atlases get large)
    out16 = out.reshape(blocks_y, blocks_x, 4, 4, 4)  # (by, bx, py, px, channel)
    image = out16.transpose(0, 2, 1, 3, 4).reshape(height, width, 4)
    return image
