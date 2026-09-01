"""
atlas_config.py — declarative config for the one-step atlas pipeline, and
the Lua metadata serializer that replaces both createAndSaveAtlas's
auto-generated metadata *and* the characterDefinitions block that used to
be hand-typed and hand-kept-in-sync with sprite indices underneath it.

Config format (JSON):

{
  "uniformWidth": 128, "uniformHeight": 128,       // optional, default 128x128
  "sources": [
    {"path": "gfx/testCharacter/walk.png", "directions": 2,
     "frameWidth": 64, "frameHeight": 128}
  ],
  "characterDefinitions": {
    "someCharacter": {
      "animations": {"walk": "gfx/testCharacter/walk.png"},
      "defaultAnimation": "walk"
    }
  }
}

characterDefinitions reference sources *by path*, not by numeric sprite
index — the pipeline resolves the index at build time. This is the actual
fragility the old workflow had: atlas_metadata3.lua's characterDefinitions
table hardcoded sprite indices that a human had to keep in sync by hand
whenever the imageFiles list above it changed order or length.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from atlas_lib import PackedAtlas, SourceSpec


def load_config(config_path: str, base_dir: str | None = None) -> tuple[list[SourceSpec], dict, int, int]:
    """Returns (sources, character_definitions, uniform_width, uniform_height).
    Source paths are resolved relative to `base_dir` (default: the config
    file's own directory) so configs are portable."""
    cfg_path = Path(config_path)
    data = json.loads(cfg_path.read_text())

    root = Path(base_dir) if base_dir is not None else cfg_path.parent
    uniform_width = data.get("uniformWidth", 128)
    uniform_height = data.get("uniformHeight", 128)

    sources: list[SourceSpec] = []
    for entry in data["sources"]:
        rel_path = entry["path"]
        resolved = str(root / rel_path)
        if not Path(resolved).exists():
            raise FileNotFoundError(
                f"source '{rel_path}' referenced by {config_path} does not exist "
                f"(resolved to {resolved}) — the pipeline validates this up front "
                f"instead of failing halfway through, unlike the old ad hoc scripts"
            )
        sources.append(SourceSpec(
            path=resolved,
            directions=entry.get("directions", 1),
            frame_width=entry.get("frameWidth"),
            frame_height=entry.get("frameHeight"),
        ))

    char_defs = data.get("characterDefinitions", {})
    _validate_character_definitions(char_defs, {s["path"] for s in data["sources"]})

    return sources, char_defs, uniform_width, uniform_height


def _validate_character_definitions(char_defs: dict, known_paths: set[str]):
    for char_name, char_def in char_defs.items():
        for anim_name, ref_path in char_def.get("animations", {}).items():
            if ref_path not in known_paths:
                raise ValueError(
                    f"characterDefinitions[{char_name!r}].animations[{anim_name!r}] "
                    f"references {ref_path!r}, which is not in `sources` — every "
                    f"character animation must point at a source path that's actually "
                    f"in this atlas"
                )
        default = char_def.get("defaultAnimation")
        if default is not None and default not in char_def.get("animations", {}):
            raise ValueError(
                f"characterDefinitions[{char_name!r}].defaultAnimation "
                f"{default!r} is not one of its own animations"
            )


def _lua_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build_metadata_lua(
    packed: PackedAtlas,
    character_definitions: dict,
    relative_image_files: list[str],
) -> str:
    """Serialize everything characterAnimator.lua's loadFromAtlas /
    calculateFrameOffsetsFromMetadata / defineCharacterTypes need, in one
    deterministic pass — no pairs()-order nondeterminism like the old
    ad hoc serializeTable() helper had."""
    # path -> 1-based global sprite index of that source's first frame,
    # for resolving characterDefinitions by path into the numeric indices
    # the runtime actually uses.
    first_frame_index: dict[str, int] = {}
    offset = 0
    for path, count in zip(relative_image_files, packed.frames_per_image):
        first_frame_index[path] = offset + 1  # Lua is 1-indexed
        offset += count

    lines: list[str] = ["return {"]
    lines.append(f'  ["spritesPerRow"] = {packed.sprites_per_row},')
    lines.append(f'  ["totalSprites"] = {packed.total_sprites},')
    lines.append(f'  ["textureWidth"] = {packed.texture_width},')
    lines.append(f'  ["textureHeight"] = {packed.texture_height},')
    lines.append(f'  ["uniformWidth"] = {packed.uniform_width},')
    lines.append(f'  ["uniformHeight"] = {packed.uniform_height},')

    lines.append('  ["framesPerImageList"] = {')
    for i, count in enumerate(packed.frames_per_image, start=1):
        lines.append(f"    [{i}] = {count},")
    lines.append("  },")

    lines.append('  ["directionsPerImageList"] = {')
    for i, d in enumerate(packed.directions_per_image, start=1):
        lines.append(f"    [{i}] = {d},")
    lines.append("  },")

    lines.append('  ["imageFiles"] = {')
    for i, path in enumerate(relative_image_files, start=1):
        lines.append(f"    [{i}] = {_lua_string(path)},")
    lines.append("  },")

    lines.append("  characterDefinitions = {")
    for char_name, char_def in character_definitions.items():
        lines.append(f"    [{_lua_string(char_name)}] = {{")
        lines.append("      animations = {")
        for anim_name, ref_path in char_def.get("animations", {}).items():
            idx = first_frame_index[ref_path]
            lines.append(f"        [{_lua_string(anim_name)}] = {idx},  -- {ref_path}")
        lines.append("      },")
        default = char_def.get("defaultAnimation")
        if default is not None:
            lines.append(f"      defaultAnimation = {_lua_string(default)},")
        lines.append("    },")
    lines.append("  },")

    lines.append("}")
    lines.append("")
    return "\n".join(lines)
