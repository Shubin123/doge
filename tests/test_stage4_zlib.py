"""
Stage 4 tests: zlib-frame the .dds bytes (what misc/compress.lua used to
do by hand, run once inside LÖVE). This stage is lossless, so unlike
stage 3 the bar here is a plain bit-exact round trip.
"""
import sys
import zlib
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parent.parent / "tools"
sys.path.insert(0, str(TOOLS))

import encode_lib  # noqa: E402


@pytest.mark.parametrize(
    "payload",
    [
        b"",
        b"\x00" * 1000,
        bytes(range(256)) * 50,
        b"DDS " + bytes((i * 37) % 256 for i in range(20000)),  # DDS-header-shaped + pseudo-random body
    ],
    ids=["empty", "all-zero", "byte-cycle", "dds-shaped"],
)
def test_zlib_roundtrip_is_bit_exact(payload):
    compressed = encode_lib.zlib_compress(payload)
    restored = encode_lib.zlib_decompress(compressed)
    assert restored == payload


def test_zlib_stream_is_standard_rfc1950_zlib():
    """love.data.decompress('data','zlib', ...) expects a standard zlib
    (RFC1950) stream — this doesn't require running LÖVE to check: a
    conformant zlib stream always starts with a specific 2-byte header
    whose 16-bit value is a multiple of 31, and Python's own zlib module
    (which is libz, same as most runtimes including LÖVE's) is the
    reference implementation of the format."""
    payload = b"hello atlas pipeline" * 100
    compressed = encode_lib.zlib_compress(payload, level=9)

    header = int.from_bytes(compressed[:2], "big")
    assert header % 31 == 0, "not a valid RFC1950 zlib header"
    cmf = compressed[0]
    assert cmf & 0x0F == 8, "expected deflate compression method"

    # and, as a completely independent check, the stdlib's own decompressobj
    # (not the convenience function) reads it back correctly too
    d = zlib.decompressobj()
    restored = d.decompress(compressed) + d.flush()
    assert restored == payload


def test_zlib_actually_shrinks_dds_sized_data():
    """Sanity check that this stage is doing its job — BC3 output still
    has structure (repeated block patterns, runs of transparent-padding
    blocks) that zlib should compress, same as the old compress.lua
    step reported when run by hand."""
    # a plausible DDS-like payload: header + many repeated all-zero /
    # near-uniform blocks (as a padded atlas would produce), plus varied
    # image blocks
    header = b"DDS " + b"\x00" * 124
    uniform_blocks = b"\x00" * 16 * 20000  # empty-padding regions compress extremely well
    varied_blocks = bytes((i * 2654435761) % 256 for i in range(16 * 2000))
    payload = header + uniform_blocks + varied_blocks

    compressed = encode_lib.zlib_compress(payload, level=9)
    assert len(compressed) < len(payload) * 0.5, "expected at least 2x reduction on padding-heavy DDS-like data"
    assert encode_lib.zlib_decompress(compressed) == payload
