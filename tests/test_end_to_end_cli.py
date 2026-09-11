"""
End-to-end test of the one-step CLI (tools/pack_atlas.py) — config JSON in,
final .dds.zlib + metadata.lua out, in a single subprocess call, using the
small fixture set (a full production-scale run needs ~2GB+ RAM and ~100s,
which was validated manually — see the delivery notes — but isn't
appropriate for a routine test run).
"""
import json
import subprocess
import sys
import zlib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
FIXTURES = ROOT / "src" / "gfx"
sys.path.insert(0, str(TOOLS))

import bc3_codec  # noqa: E402


@pytest.fixture(scope="module")
def built(tmp_path_factory):
    workdir = tmp_path_factory.mktemp("e2e")
    config = {
        "uniformWidth": 128,
        "uniformHeight": 128,
        "sources": [
            {"path": "DancingGirlSheets/hips.png", "directions": 6, "frameWidth": 52, "frameHeight": 53},
            {"path": "testCharacter/idle.png", "directions": 2, "frameWidth": 64, "frameHeight": 128},
            {"path": "watchmanOfDoom_lowres/idle.png", "directions": 8, "frameWidth": 128, "frameHeight": 128},
        ],
        "characterDefinitions": {
            "watchman": {
                "animations": {"idle": "watchmanOfDoom_lowres/idle.png"},
                "defaultAnimation": "idle",
            },
            "dancer": {
                "animations": {"hips": "DancingGirlSheets/hips.png"},
                "defaultAnimation": "hips",
            },
        },
    }
    config_path = workdir / "config.json"
    config_path.write_text(json.dumps(config))

    out_atlas = workdir / "atla.dds.zlib"
    out_meta = workdir / "atlas_metadata.lua"

    result = subprocess.run(
        [sys.executable, str(TOOLS / "pack_atlas.py"),
         "--config", str(config_path),
         "--gfx-root", str(FIXTURES),
         "--out-atlas", str(out_atlas),
         "--out-metadata", str(out_meta)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, f"pack_atlas.py failed:\n{result.stdout}\n{result.stderr}"
    return {"stdout": result.stdout, "out_atlas": out_atlas, "out_meta": out_meta, "config": config}


def test_cli_reports_success_and_writes_both_outputs(built):
    assert "done in" in built["stdout"]
    assert built["out_atlas"].exists()
    assert built["out_meta"].exists()
    assert built["out_atlas"].stat().st_size > 0


def test_output_atlas_decompresses_and_decodes(built):
    compressed = built["out_atlas"].read_bytes()
    dds = zlib.decompress(compressed)
    assert dds[:4] == b"DDS "
    w, h = bc3_codec.read_dds_dimensions(dds)
    decoded = bc3_codec.decode_bc3(dds, w, h)
    assert decoded.shape == (h, w, 4)
    assert decoded[:, :, 3].max() > 0, "decoded atlas is entirely transparent — something is badly wrong"


def test_metadata_loads_in_real_lua_and_is_self_consistent(built):
    lua_script = f"""
    local m = dofile({json.dumps(str(built['out_meta']))})
    local sum = 0
    for i, v in ipairs(m.framesPerImageList) do sum = sum + v end
    assert(sum == m.totalSprites, "framesPerImageList sum != totalSprites")
    assert(#m.imageFiles == #m.framesPerImageList)
    assert(m.characterDefinitions.watchman.animations.idle ~= nil)
    assert(m.characterDefinitions.dancer.animations.hips ~= nil)
    print("OK", m.totalSprites, m.textureWidth, m.spritesPerRow)
    """
    result = subprocess.run(["lua5.4", "-e", lua_script], capture_output=True, text=True)
    assert result.returncode == 0, f"metadata failed real-Lua validation:\n{result.stdout}\n{result.stderr}"
    assert result.stdout.startswith("OK")


def test_character_definition_indices_point_at_the_right_sprites(built):
    """The whole point of resolving characterDefinitions by path instead of
    hand-typed index: prove the resolved index actually lands on the
    sprite it's supposed to."""
    lua_script = f"""
    local m = dofile({json.dumps(str(built['out_meta']))})
    print(m.characterDefinitions.watchman.animations.idle)
    print(m.imageFiles[1])
    """
    result = subprocess.run(["lua5.4", "-e", lua_script], capture_output=True, text=True, check=True)
    idle_index, first_image = result.stdout.strip().splitlines()
    idle_index = int(idle_index)

    # first frame of watchmanOfDoom_lowres/idle.png should be the 3rd
    # source in our config (after hips.png's 6 frames and idle.png's 4
    # frames from testCharacter) -> global index 6+4+1 = 11 (1-based)
    assert idle_index == 6 + 4 + 1
