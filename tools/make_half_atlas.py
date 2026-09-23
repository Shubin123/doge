#!/usr/bin/env python3
"""
make_half_atlas.py — derive the half-resolution fallback atlas.

The main atlas is one 16384x16384 BC3/DXT5 texture. GPUs/drivers that cap
textures at 8192 (older iGPUs, SwiftShader on CI) cannot upload it, and
sprites silently draw as solid quads. This writes an 8192x8192 copy with
the *same grid* (128 cells per row, now 64px each), so the existing
metadata and normalized UVs work unchanged; characterAnimator.loadFromAtlas
picks it when love.graphics.getSystemLimits().texturesize < 16384.

    python3 tools/make_half_atlas.py \\
        --in src/gfx/atlas/atla.dds.zlib --out src/gfx/atlas/atla_8k.dds.zlib

pack_atlas.py runs this automatically after writing the main atlas.
Decoding streams in horizontal strips, so peak memory stays ~0.4 GB.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from bc3_codec import DDS_HEADER_SIZE, decode_bc3, read_dds_dimensions  # noqa: E402
from encode_lib import encode_rgba_to_dds_bytes, zlib_compress, zlib_decompress  # noqa: E402

STRIP_ROWS = 512  # source pixel rows decoded at a time (multiple of 4 and 2)


def downsample2x(rgba: np.ndarray) -> np.ndarray:
    """2x2 box filter. Colour is alpha-weighted so transparent padding does
    not darken sprite edges; fully transparent blocks keep their (dilated)
    colour so BC3 does not fringe."""
    f = rgba.astype(np.float32)
    h, w = f.shape[0] // 2, f.shape[1] // 2
    q = f.reshape(h, 2, w, 2, 4)
    a = q[..., 3:4]
    asum = a.sum(axis=(1, 3))
    weighted = (q[..., :3] * a).sum(axis=(1, 3))
    plain = q[..., :3].mean(axis=(1, 3))
    rgb = np.where(asum > 0, weighted / np.maximum(asum, 1e-6), plain)
    out = np.concatenate([rgb, asum / 4.0], axis=-1)
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def half_atlas(dds: bytes) -> np.ndarray:
    width, height = read_dds_dimensions(dds)
    row_bytes = (width // 4) * 16  # one row of 4x4 BC3 blocks
    out = np.zeros((height // 2, width // 2, 4), dtype=np.uint8)
    for y in range(0, height, STRIP_ROWS):
        rows = min(STRIP_ROWS, height - y)
        start = DDS_HEADER_SIZE + (y // 4) * row_bytes
        strip = decode_bc3(dds[start:start + (rows // 4) * row_bytes], width, rows, header_offset=0)
        out[y // 2:(y + rows) // 2] = downsample2x(strip)
        print(f"\r  decoded {y + rows}/{height} rows", end="", flush=True)
    print()
    return out


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--in", dest="src", default="src/gfx/atlas/atla.dds.zlib")
    p.add_argument("--out", default="src/gfx/atlas/atla_8k.dds.zlib")
    args = p.parse_args(argv)

    t0 = time.time()
    dds = zlib_decompress(Path(args.src).read_bytes())
    w, h = read_dds_dimensions(dds)
    print(f"half atlas: {args.src} {w}x{h} -> {w // 2}x{h // 2}")
    small = half_atlas(dds)
    packed = zlib_compress(encode_rgba_to_dds_bytes(small))
    Path(args.out).write_bytes(packed)
    print(f"wrote {args.out} ({len(packed) / 1048576:.1f} MB) in {time.time() - t0:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
