# Asset → build → deploy pipeline

One page covering how art gets into the game and how the game gets to
players. Deeper references: `tools/README.md` (atlas config and flags),
`tests/README.md` (atlas pipeline tests), `README.md` (engine features).

```
 3D model (.fbx/.glb/.blend, e.g. Mixamo)
        │  tools/render_sprites.py      (Blender, headless — replaces Unity)
        ▼
 sprite sheet PNG  8 cols (directions) × N rows (frames), 128×128 cells
 [+ optional _normals.png, same layout]
        │  configs/production_atlas.json   (add the sheet + an animation name)
        │  tools/pack_atlas.py             (slice → pack → BC3/DXT5 → zlib)
        ▼
 src/gfx/atlas/atla.dds.zlib  +  src/gfx/atlas/atlas_metadata3.lua
        │  characterAnimator.loadFromAtlas()   (src/main.lua)
        ▼
 game:  instance.setCharacterType("name") / instance.setAnimation("walk")
        │  tools/make_love.sh   (src/ minus tools/shipping-excludes.txt → dist/doge.love)
        │  ./buildjs.sh         (Lua 5.1 check, love.js compat + custom S3TC engine → dist/web)
        ▼
 CI  .github/workflows/pages.yml  (push to main)
        build → e2e framebuffer smoke → deploy Pages → verify live commit + e2e on live URL
        every 6h: live check, redeploys main if it fails
```

---

## 1. Sprite sheet format (the contract)

Everything downstream assumes this layout:

| | |
|---|---|
| Cell | 128×128 px, transparent background (atlas uniform size) |
| Columns | 8 facing directions |
| Rows | animation frames, top to bottom |
| Sheet size | 1024 × (128 × frames) |

Direction columns, as picked by `Enemy:getDirectionToPlayer` /
`player.getHeading` (`atan2(dx, dy)` in 45° sectors):

| col | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| faces | camera (down) | down-right | right | up-right | away (up) | up-left | left | down-left |

`characterAnimator` treats a sheet as 8-directional when its frame count is
a multiple of 8, and indexes `offset + (frame-1)*8 + (direction-1)`, so
frames are read row by row. Single-direction props (guns, vehicles) use other
column counts; set `"directions"` in the config to match the sheet.

## 2. Adding a new 3D animation (no Unity)

Needs Blender 2.93+ (`/Applications/Blender.app`), Python 3 with Pillow and
numpy, and a C compiler (for `bc-encoder`, built automatically).

**a. Get an animated model.** Mixamo works well: pick a character, pick an
animation, download *FBX Binary, With Skin*, 30 fps. For more animations of
the same character, download each one (or one .blend with several actions).
The model should face Blender's front (-Y) at rest.

**b. Render the sheet.**

```sh
B=/Applications/Blender.app/Contents/MacOS/Blender

# what animations does the file have?
$B -b -P tools/render_sprites.py -- --model ~/Downloads/knight_walk.fbx --list

# render (16 frames, 8 directions, plus a normal-map sheet for lighting)
$B -b -P tools/render_sprites.py -- --model ~/Downloads/knight_walk.fbx \
    --action "mixamo.com" --frames 16 --normals \
    --out src/gfx/3d/knight/walk.png
```

It prints the auto-fitted `ortho_scale`. **Pass that same `--ortho-scale` to
every other animation of this character** (run, attack, death…) so they
render at the same size and don't pop when the animation switches. Useful
flags: `--elevation` (camera pitch, default 30°, which matches the existing
art), `--yaw 180` if the model faces away at rest, `--cell` (keep 128),
`--samples`. `--demo` renders a built-in test figure: a quick way to check the
direction order without an asset.

Keep frame counts modest: every 8-direction frame costs 8 atlas cells (see
§4). 12–24 frames per loop is plenty at 128 px.

**c. Register it in the atlas config** — `configs/production_atlas.json`:

```json
"sources": [
  ...,
  { "path": "gfx/3d/knight/walk.png", "directions": 8, "frameWidth": 128, "frameHeight": 128 }
],
"characterDefinitions": {
  ...,
  "knight": {
    "animations": { "walk": "gfx/3d/knight/walk.png" },
    "defaultAnimation": "walk"
  }
}
```

Animations are referenced by *path*; `pack_atlas.py` works out sprite
indices, so there is nothing to hand-sync.

**d. Rebuild the atlas.** The game loads `atlas_metadata3.lua`, so write to
that file:

```sh
python3 tools/pack_atlas.py --config configs/production_atlas.json --gfx-root src \
    --out-atlas src/gfx/atlas/atla.dds.zlib \
    --out-metadata src/gfx/atlas/atlas_metadata3.lua \
    --dump-atlas-png /tmp/atlas_check.png      # optional visual check
```

> **Before the first rebuild:** the shipping atlas was made by the old
> process and has four sprites whose source PNGs are no longer in the repo
> (`tree`, `arch`, `coin`, `house` from `gfx/TileSet/`). The config omits
> them (see its `_notes`), so a rebuild drops those character types. Re-add
> the source sheets first, or check nothing you care about uses them.

**e. Use it in code.**

```lua
local k = gun_enemies[i]            -- any instance from loadFromAtlas()
k.setCharacterType("knight")        -- starts its defaultAnimation
k.setAnimation("walk")              -- switch animations by name
k.setDirection(e:getDirectionToPlayer() or 1)   -- 1..8, see §1
```

**f. Check it.** `./run.sh` (desktop, hot-reload), then `./buildjs.sh` and
`npm run test:web:smoke` for the browser build (§5).

**Normal maps.** `--normals` writes `<name>_normals.png` in the same layout:
screen-space normals encoded `n*0.5+0.5` (x right, y down, z toward viewer),
which is what the sprite shader decodes (`normal = tex*2-1`). Right now the
shader only binds one normal map, the princess walk sheet, in
`characterAnimator.lua` (`NormalTex`). Lighting a new character that way
means binding its sheet there too; the colour sheet works without it.

## 3. What `pack_atlas.py` does

1. Load the config and check that every source path exists.
2. Slice each sheet into 128×128 cells in row-major order, then pack them
   into a 16384² atlas (128 cells per row).
3. Dilate alpha edges and encode BC3/DXT5 with `bc-encoder` (stb_dxt). The
   format is 4:1 versus RGBA8 and the GPU decodes it natively.
4. zlib the `.dds` → `atla.dds.zlib` (~9 MB). The game inflates it with
   `love.data.decompress`, then calls `love.image.newCompressedData` and
   `newImage`.
5. Write the metadata Lua (image list, frame counts, characterDefinitions).

Tests: `pytest tests/` checks each stage. Details in `tests/README.md`.

## 4. Budgets and platform limits

- **Atlas capacity:** 16384 cells, and 6759 are used today. One 8-direction
  animation with 16 frames takes 128 cells, so there's room for about 75 more.
  Going beyond 16384² would break the texture-size limit below.
- **GPU format:** BC3/DXT5 (S3TC). Desktop GPUs expose it on Windows, macOS
  and Linux (in browsers too, via ANGLE). Mobile GPUs mostly expose only
  ETC2/ASTC, and some older iGPUs cap textures at 8192. The web page checks
  both before downloading anything and names the missing capability and the
  GPU. The Lua loader raises the same reasons on desktop builds. Supporting
  those devices would take a second atlas encode (e.g. ETC2/ASTC in KTX) and
  a runtime choice between the two; that doesn't exist yet.
- **Web memory:** the love.js heap is fixed at 1.5 GiB (`LOVEJS_MEMORY`).
  The atlas is 256 MB while it decodes. Raise the heap if the atlas grows.
- **Web Lua is 5.1:** no `goto`, labels or other 5.2+ syntax.
  `tools/check_lua51.py` enforces this in `buildjs.sh`.

## 5. Build, test, deploy

| Command | Result |
|---|---|
| `./run.sh` | desktop, hot reload |
| `tools/make_love.sh` | `dist/doge.love` (excludes atlas sources, see `tools/shipping-excludes.txt`) |
| `./build.sh` | `.love` + macOS `.app` + Windows `.exe` |
| `./buildjs.sh` | `dist/web/` using the custom S3TC love engine in `tools/web/custom-love/` |
| `npm run test:web` | build web + e2e smoke |

The e2e smoke test (`tools/test_web_smoke.js`) serves `dist/web` (or
`WEB_URL=...`) in Chrome. It fails on any of these:

- a fake GPU without S3TC, or with 8192 max textures, doesn't get a clear
  "Unsupported GPU" message, or still downloads the engine
- missing files, JS errors, DXT5 or shader-link errors, or an engine alert
- the game doesn't reach 80 enemies
- after 15 s of play (firing throughout), the canvas pixels are black, flat,
  frozen over 1 s, or don't change when walking with WASD
- fps falls below `SMOKE_MIN_FPS` (0.2 on GPU-less CI runners, 1 locally)
- the HTML sound/lights controls don't reach LÖVE

Frames are saved to `dist/e2e/` and uploaded as a CI artifact.

**CI/CD** (`.github/workflows/pages.yml`): only `main` deploys. PRs run
build + e2e without deploying. After a deploy, CI waits until
`https://shubin123.github.io/doge/version.txt` shows the new commit, then
runs the e2e against the live site. A scheduled job repeats that check
every 6 h and redeploys `main` if it fails. Runs take ~12 min because the
runners render in software.

Branches that are fully merged into `main` get renamed `STAIL/<name>`.
