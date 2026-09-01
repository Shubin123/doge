#!/usr/bin/env python3
"""
pack_atlas.py — the one-step sprite atlas encoder pipeline.

Replaces what used to be four separate manual steps:

  1. uncomment/edit a characterAnimator.createAndSaveAtlas(...) call in
     main.lua, run the game once to generate atlas.png + atlas_metadata.lua,
     then comment it back out
  2. compile bc-encoder by hand and run it on atlas.png to get a .dds
  3. run misc/compress.lua inside LÖVE by hand to zlib the .dds
  4. hand-edit main.lua again to point at the new files, and hand-edit the
     metadata's characterDefinitions table to match whatever sprite indices
     step 1 happened to produce this time

...into one command:

    python3 tools/pack_atlas.py --config configs/example_atlas.json \\
        --gfx-root src/gfx \\
        --out-atlas src/gfx/atlas/atla.dds.zlib \\
        --out-metadata src/gfx/atlas/atlas_metadata.lua

Source sheets can come from anywhere (a Unity grid export, Aseprite, a
hand-drawn sheet) — the config just needs a path + how many "direction"
columns it's laid out in; gathering is the config, not a code change.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import atlas_lib  # noqa: E402
import encode_lib  # noqa: E402
from atlas_config import build_metadata_lua, load_config  # noqa: E402


def human_bytes(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f}{unit}" if unit != "B" else f"{n}B"
        n /= 1024
    return f"{n:.1f}TB"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", required=True, help="path to the atlas config JSON")
    parser.add_argument("--gfx-root", default=None,
                         help="directory source paths in the config are relative to "
                              "(default: the config file's own directory)")
    parser.add_argument("--out-atlas", required=True,
                         help="output path for the final compressed atlas, e.g. src/gfx/atlas/atla.dds.zlib")
    parser.add_argument("--out-metadata", required=True,
                         help="output path for the atlas metadata Lua file")
    parser.add_argument("--dump-atlas-png", default=None,
                         help="optional: also write the uncompressed RGBA atlas as a PNG, for visual QA")
    parser.add_argument("--no-compress", action="store_true",
                         help="skip the zlib framing step and write a raw .dds instead")
    parser.add_argument("--no-dilate", action="store_true",
                         help="skip alpha-padding dilation before BC3 encoding (not recommended — "
                              "see atlas_lib.dilate_alpha_padding)")
    parser.add_argument("--dilate-iterations", type=int, default=4)
    args = parser.parse_args(argv)

    t0 = time.time()

    print(f"[1/4] loading config {args.config} ...")
    sources, char_defs, uw, uh = load_config(args.config, base_dir=args.gfx_root)
    print(f"      {len(sources)} source sheet(s), uniform tile {uw}x{uh}")

    print("[2/4] extracting frames + packing atlas ...")
    if not args.no_dilate:
        print(f"      (dilating alpha padding per-tile, {args.dilate_iterations} iterations, "
              f"to avoid BC3 edge fringing)")
    packed = atlas_lib.pack_atlas(
        sources, uw, uh,
        dilate=not args.no_dilate, dilate_iterations=args.dilate_iterations,
    )
    total_src_bytes = sum(Path(s.path).stat().st_size for s in sources)
    atlas_rgba_bytes = packed.image.nbytes
    print(f"      {packed.total_sprites} sprites -> {packed.texture_width}x{packed.texture_height} atlas "
          f"({human_bytes(atlas_rgba_bytes)} raw RGBA, from {human_bytes(total_src_bytes)} of source PNGs)")

    if args.dump_atlas_png:
        from PIL import Image
        Image.fromarray(packed.image, mode="RGBA").save(args.dump_atlas_png)
        print(f"      wrote debug atlas PNG: {args.dump_atlas_png}")

    print("[3/4] BC3/DXT5 encoding ...")
    dds_bytes = encode_lib.encode_rgba_to_dds_bytes(packed.image)
    print(f"      {human_bytes(len(dds_bytes))} ({atlas_rgba_bytes / len(dds_bytes):.2f}x smaller than raw RGBA)")

    if args.no_compress:
        final_bytes = dds_bytes
        out_atlas_path = Path(args.out_atlas)
    else:
        print("[4/4] zlib compressing ...")
        final_bytes = encode_lib.zlib_compress(dds_bytes)
        out_atlas_path = Path(args.out_atlas)
        print(f"      {human_bytes(len(final_bytes))} ({len(dds_bytes) / len(final_bytes):.2f}x smaller than .dds)")

    out_atlas_path.parent.mkdir(parents=True, exist_ok=True)
    out_atlas_path.write_bytes(final_bytes)

    relative_image_files = [entry["path"] for entry in __import__("json").loads(Path(args.config).read_text())["sources"]]
    metadata_lua = build_metadata_lua(packed, char_defs, relative_image_files)
    out_meta_path = Path(args.out_metadata)
    out_meta_path.parent.mkdir(parents=True, exist_ok=True)
    out_meta_path.write_text(metadata_lua)

    elapsed = time.time() - t0
    print(f"\ndone in {elapsed:.1f}s")
    print(f"  atlas:    {out_atlas_path} ({human_bytes(out_atlas_path.stat().st_size)})")
    print(f"  metadata: {out_meta_path}")
    print(f"\n  overall: {human_bytes(total_src_bytes)} of sources -> {human_bytes(out_atlas_path.stat().st_size)} "
          f"({total_src_bytes / out_atlas_path.stat().st_size:.1f}x)")
    print(f"\n  load with: characterAnimator.loadFromAtlas({_rel(args.out_atlas)!r}, {_rel(args.out_metadata)!r}, "
          f"{'false' if args.no_compress else 'true'})")
    return 0


def _rel(p: str) -> str:
    # best-effort: strip a leading "src/" since that's what's passed to
    # love.filesystem.* at runtime (LÖVE's working directory is src/)
    s = str(p)
    return s[4:] if s.startswith("src/") else s


if __name__ == "__main__":
    raise SystemExit(main())
