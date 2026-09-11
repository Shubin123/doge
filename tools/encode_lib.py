"""
encode_lib.py — the "encode for size" half of the pipeline: BC3/DXT5 block
compression (via the existing, proven `bc-encoder` C tool) plus zlib
framing, wired up so nothing has to be run by hand.

This is what used to be two separate manual steps:
  - compile & run bc-encoder on the atlas PNG to get a .dds
  - run misc/compress.lua inside LÖVE to zlib the .dds

Both now happen as plain function calls, with the C encoder auto-built the
first time it's needed.
"""
from __future__ import annotations

import subprocess
import tempfile
import zlib
from pathlib import Path

import numpy as np
from PIL import Image

BC_ENCODER_DIR = Path(__file__).resolve().parent.parent / "bc-encoder"
BC_ENCODER_BIN = BC_ENCODER_DIR / "bc3enc"


def ensure_bc_encoder_built() -> Path:
    """Compile bc-encoder/main.c into bc3enc if it isn't already built.
    This is the one-time bootstrap step that replaces having to remember
    to `gcc` it by hand before running the pipeline."""
    if BC_ENCODER_BIN.exists():
        return BC_ENCODER_BIN

    main_c = BC_ENCODER_DIR / "main.c"
    if not main_c.exists():
        raise FileNotFoundError(f"bc-encoder source not found at {main_c}")

    # Try an OpenMP build first (parallel block compression — matters a lot
    # on a production-sized 8k-16k atlas), falling back to a plain serial
    # build on toolchains without OpenMP so the pipeline still works.
    for extra_flags in (["-fopenmp"], []):
        result = subprocess.run(
            ["gcc", "-O2", *extra_flags, "-o", str(BC_ENCODER_BIN), str(main_c), "-lm"],
            capture_output=True, text=True, cwd=str(BC_ENCODER_DIR),
        )
        if result.returncode == 0:
            return BC_ENCODER_BIN
    raise RuntimeError(f"failed to build bc-encoder:\n{result.stdout}\n{result.stderr}")


def encode_rgba_to_dds_bytes(rgba: np.ndarray) -> bytes:
    """BC3/DXT5-encode an (H,W,4) uint8 RGBA array, return raw .dds bytes.

    Internally shells out to the compiled bc-encoder binary (auto-built on
    first use) via a temp PNG in/DDS out round trip — the temp files never
    touch the caller's filesystem layout, so from the outside this is just
    a function call.
    """
    binary = ensure_bc_encoder_built()

    with tempfile.TemporaryDirectory() as tmp:
        tmp_png = Path(tmp) / "atlas.png"
        tmp_dds = Path(tmp) / "atlas.dds"
        Image.fromarray(rgba, mode="RGBA").save(tmp_png)

        result = subprocess.run(
            [str(binary), str(tmp_png), str(tmp_dds)],
            capture_output=True, text=True,
        )
        if result.returncode != 0 or not tmp_dds.exists():
            raise RuntimeError(f"bc-encoder failed:\n{result.stdout}\n{result.stderr}")

        return tmp_dds.read_bytes()


def zlib_compress(data: bytes, level: int = 9) -> bytes:
    """Same call misc/compress.lua made (love.data.compress('data','zlib',
    data, 9)) — a standard RFC1950 zlib stream, decompressible from LÖVE
    with love.data.decompress('data', 'zlib', ...) regardless of which
    zlib implementation produced it."""
    return zlib.compress(data, level)


def zlib_decompress(data: bytes) -> bytes:
    return zlib.decompress(data)
