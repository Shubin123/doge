![Screenshot 2025-05-16 at 9 03 05 PM](https://github.com/user-attachments/assets/43569a98-3479-4edf-8905-a9d768210be9)
![Screenshot 2025-05-24 at 1 47 35 AM](https://github.com/user-attachments/assets/9c959565-c9f8-4ceb-9ea5-f9ac615b4ff3)


# LÖVE2D Real-Time Global Illumination & Water Effects

A 2D game engine implementation featuring real-time global illumination using Jump Flood Algorithm (JFA) and realistic water shader effects, built with LÖVE2D (Lua).

## Features

### 🌟 Real-Time Global Illumination
- **Jump Flood Algorithm (JFA)** implementation for efficient distance field generation
- **Ray marching** for realistic light bouncing and ambient occlusion
- **Configurable sampling** with adjustable ray count and maximum distance
- **Optimized rendering** with multi-pass shader pipeline

### 🌊 Advanced Water Effects
- **Real-time water distortion** with animated ripples and waves
- **Reflection mapping** for realistic water surface reflections  
- **World-space positioning** that works correctly with camera movement and zoom
- **Noise-based animation** for natural water movement patterns

### 📷 Smooth Camera System
- **Interpolated following** with configurable smoothing speed
- **Smooth zoom** with independent zoom speed control
- **Sub-pixel stability** using floor operations to prevent jitter
- **Frame-rate independent** smoothing options

## Technical Implementation

### Global Illumination Pipeline

1. **Scene Rendering**: Objects are rendered to a scene canvas
2. **Seed Pass**: Visible surfaces are converted to UV coordinates
3. **Jump Flood Algorithm**: Multi-pass distance field generation using ping-pong buffers
4. **Distance Field**: Calculate distances from UV coordinates
5. **Ray Marching**: Cast rays in all directions to gather ambient light

```lua
-- Basic usage
shader.prepass()
-- Draw your game objects here
shader.pass(maxDistance, sampleCount)
```

### Water Shader System

The water system uses world-space coordinates to maintain position consistency:

```lua
-- Set water area in world coordinates
water.setWaterArea(x, y, width, height)

-- Update with camera transform
water.setCameraTransform(camera.x, camera.y, camera.zoom)
water.update(dt)

-- Render water effects
water.pass()
```

### Camera System

Smooth camera following with configurable interpolation:

```lua
local camera = require("camera")

-- Update camera each frame
camera.update(dt, player)

-- Set zoom level
camera.setZoom(2.0) -- 2x zoom

-- Apply camera transform
love.graphics.push()
camera.apply()
-- Draw world objects here
love.graphics.pop()
```

## Shader Requirements

### Canvas Formats
- **Scene Canvas**: `rgba8` format for color rendering
- **JFA Canvases**: `rg16f` format for UV coordinate storage
- **Distance Field**: `r16f` format for distance values
- **Water Canvases**: `rgba8` format for water effects

### External Assets
- **Noise Texture**: `gfx/noise.png` - Required for water distortion effects

## Performance Considerations

### Global Illumination
- **Sample Count**: Lower values (16-32) for real-time, higher (64+) for quality
- **Max Distance**: Tune based on scene size to balance quality vs performance
- **JFA Passes**: Automatically calculated based on screen resolution

### Water Effects
- **Noise Scale**: Affects detail level of water distortion
- **Distortion Strength**: Controls intensity of water warping
- **Update Frequency**: Water animation updates can be throttled if needed

## Configuration Variables

```lua
-- Global Illumination
local maxDistance = 40    -- Maximum ray marching distance
local sampleCount = 32    -- Number of rays per pixel

-- Water Effects
local distortionStrength = 0.015  -- Water distortion intensity
local reflectionStrength = 0.1    -- Reflection opacity

-- Camera
local lerpSpeed = 0.1            -- Camera following speed
local zoomLerpSpeed = 0.1        -- Zoom transition speed

## Usage Example

```lua
function love.load()
    shader.load()
    water.load()
    -- Initialize other systems
end

function love.update(dt)
    -- Update camera
    camera.update(dt, player)
    
    -- Update water with camera transform
    water.setCameraTransform(camera.x, camera.y, camera.zoom)
    water.update(dt)
    
    -- Set water areas in world space
    water.setWaterArea(100, 200, 300, 150)
end

function love.draw()
    love.graphics.push()
    camera.apply()
    
    -- Render scene with global illumination
    shader.prepass()
    -- Draw your game objects here
    shader.pass(40, 32) -- maxDistance=40, samples=32
    
    love.graphics.pop()
    
    -- Apply water effects
    water.pass()
end
```

## Requirements

- **LÖVE2D 11.3+** with OpenGL 3.3+ support (put into /applications/ folder)
- **GPU** with floating-point texture support
- **Shader Model 3.0+** compatibility

## Performance Tips

1. **Batch draw calls** within shader.prepass() and shader.pass()
2. **Use lower sample counts** during gameplay, higher for screenshots
3. **Limit water areas** to visible regions only
4. **Profile regularly** - GPU profiling tools help identify bottlenecks
5. **Consider LOD** - reduce effect quality at distance

## Sprite Atlas Pipeline

**Full walkthrough, including rendering new 3D animations with Blender
(`tools/render_sprites.py`, no Unity): `docs/PIPELINE.md`.**

Character/object sprites (rendered with `tools/render_sprites.py`, Aseprite,
a hand-drawn sheet) are packed into one texture atlas
and BC3/DXT5-compressed for size before shipping. That used to be four
manual steps (build the atlas from inside LÖVE, compile and run a
separate C tool to BC3-encode it, run another LÖVE script by hand to
zlib-compress the result, then hand-edit main.lua and a metadata table to
match). It's now one command:

```sh
python3 tools/pack_atlas.py \
  --config configs/production_atlas.json \
  --gfx-root src \
  --out-atlas src/gfx/atlas/atla.dds.zlib \
  --out-metadata src/gfx/atlas/atlas_metadata3.lua   # the file main.lua loads
```

Requires Python 3 + Pillow + numpy, and a C compiler (gcc) to build
`bc-encoder/` the first time — the tool does that automatically. See
`tools/README.md` for the config format and `tests/` for
the pipeline's own test suite (bit-exact checks on the lossless stages,
PSNR/visual-diff checks on the lossy BC3 stage, all run against real
sprites from `src/gfx/`).

## Building & Publishing

### Desktop

```sh
./run.sh                 # run from source, hot-reloaded
tools/make_love.sh       # -> dist/doge.love
./build.sh               # -> dist/doge.love + .app (macOS) + .exe (Windows)
```

`tools/make_love.sh` packages `src/` minus `tools/shipping-excludes.txt`.
That list is the atlas *source* sheets and stale pipeline artifacts — inputs
to `tools/pack_atlas.py`, never opened by the running game. It takes the
package from ~160 MB to ~33 MB. The list was derived by running the game with
every image/audio/file load traced and dropping only files over 1 MB that were
never touched; anything smaller ships regardless, so a rarely-hit lazy load
can't silently lose its art.

### Web (WebAssembly)

```sh
./buildjs.sh             # -> dist/web/
python3 -m http.server -d dist/web 8080
```

`file://` will not work — wasm needs to be served over http.

Two constraints are baked into `buildjs.sh` and worth knowing before changing it:

- **The compat runtime (`-c`) is mandatory.** love.js's default "release"
  runtime is threaded, which requires `SharedArrayBuffer`, which requires the
  COOP/COEP response headers — and GitHub Pages cannot set headers. The compat
  runtime is single-threaded and runs on any static host.
- **The web runtime is plain Lua 5.1, not LuaJIT.** `goto`/`::labels::` and
  other 5.2+ syntax compile fine on desktop and are a fatal parse error in the
  browser, before the first frame. `tools/check_lua51.py` runs as the first
  step of `buildjs.sh` to catch that class of bug; neither LuaJIT nor a modern
  system `lua` will.

The heap size (`-m`) is fixed at build time and is dominated by the atlas:
8.8 MB on disk unpacks to a 16384×16384 DXT5 surface — 256 MB — that is briefly
resident before it goes to the GPU. Override with `LOVEJS_MEMORY=... ./buildjs.sh`
if you change the atlas.

Because the atlas ships as BC3/DXT5, the browser must expose
`WEBGL_compressed_texture_s3tc` and support 16384px textures. Desktop Chrome,
Firefox and Edge do (including on Apple silicon, via ANGLE). The page checks
both up front and explains the problem rather than dying inside a texture load.

### GitHub Pages

`.github/workflows/pages.yml` builds the web bundle, runs the e2e framebuffer
smoke test, and deploys it on every push to `main` (then re-verifies the live
site; see `docs/PIPELINE.md`). It needs Pages switched on once, in
**Settings → Pages → Build and deployment → Source: GitHub Actions**.

## Known Limitations

- No localStorage/sessionStorage support in LÖVE2D artifacts
- Requires modern GPU with floating-point texture support  
- Performance scales with screen resolution and sample count
- Water reflections are approximated, not true ray-traced reflections

## License

This project demonstrates advanced 2D rendering techniques and is provided as-is for educational and development purposes.
