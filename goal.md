# DOGE Game — Performance Goals & Roadmap

## Current TODO (from todo file)

- [ ] add statics and obstacles (indoor?)
- [ ] add player unlocks
- [x] use enemy animations
- [x] serialization on windows not working
- [x] grouped collision for instances
- [ ] indoor lighting (block everything outside)
- [ ] auto arrows, auto bullets, melee attack, melee grab, auto melee
- [x] change shockwave shader run after instance drawn
- [x] atlas pipeline: one-step tools/pack_atlas.py (see README's "Sprite Atlas Pipeline" section)
- [ ] re-source 4 missing TileSet sprites the old atlas config referenced (tree1.png, arch.png, coin128.png, house128.png)

---

## Performance Initiative

### Problem
Large numbers of entities cause significant lag. No profiling infrastructure exists. No automated benchmarks.

### Goal
Add profiling/benchmark hooks, identify and fix bottlenecks, write benchmark tests. Target: maintain 60 FPS at 2× current entity counts.

---

## Architecture Overview

- **Engine**: LÖVE2D (Love2D) Lua game framework
- **Physics**: Box2D via `love.physics` — all entities have physics bodies
- **Rendering**: Y-sorted `dynamic_draw_list` rebuilt every frame, sorted with `table.sort`
- **Characters**: GPU-instanced rendering via `characterAnimator.lua` (custom mesh+shader pipeline)
- **AI**: Custom behaviour tree library (`src/lib/behaviourTrees/`)
- **Collision**: Centralized system with group-index routing (`src/util/collision.lua`)
- **Multiplayer**: Lua-enet based (`src/network/multiplayer.lua`)
- **Post-processing**: Moonshine library for glow/blur/godsray/crt effects

---

## Performance Bottlenecks Found

### CPU — Critical (fix first)

| # | Issue | File | Impact |
|---|-------|------|--------|
| 1 | `pcall` per projectile update | `enemy.lua:146` | ~100 pcall calls/frame |
| 2 | `canvas:newImageData()` on bullet-enemy hit | `collision.lua:259` | Extremely slow per-collision |
| 3 | Table allocation storm (~150-300 tables/frame) | `renderer.lua` + all `populate()` | GC thrashing |
| 4 | Behaviour tree walked every frame per enemy | `enemy.lua:267` | Wasted when no target nearby |
| 5 | No viewport culling | All `populate()` functions | Biggest missed CPU opt |
| 6 | Boss raycast closure per frame | `boss.lua:577` | GC alloc per boss |

### GPU — Critical

| # | Issue | File | Impact |
|---|-------|------|--------|
| 7 | Shadow shader 350 iterations/pixel | `shadow.lua` shader | ~700M shader iters/frame at 1080p |
| 8 | `unpack(lightData)` may overflow Lua stack | `shadow.lua:160` | Silent truncation/crash with many lights |
| 9 | Moonshine multi-pass every frame | `light.lua` | 3+ full-screen passes per light chain |
| 10 | Full-canvas ping-pong for shockwave | `explosion.lua` | 2 full-screen draws per explosion |

### CPU — Secondary

| # | Issue | File | Impact |
|---|-------|------|--------|
| 11 | `last_color` reference bug (skip optimization broken) | `renderer.lua:789` | Redundant `setColor` calls |
| 12 | Redundant shader switches in render loop | `renderer.lua` | GPU state thrashing |
| 13 | No spatial partitioning for distance checks | `enemy.lua` | O(n²) distance calcs |
| 14 | Enemy projectiles use physics bodies | `enemy.lua:134-135` | Box2D alloc per projectile |
| 15 | `addPlayer()` body fully commented out | `renderer.lua:146-166` | Dead call every frame |
| 16 | Exhaust particles sim'd but never drawn | `rocket.lua:102-116` | CPU waste |
| 17 | `math.cos/sin` per enemy per frame | `enemy.lua:619-620` | Unnecessary trig |

---

## Implementation Steps

### Step 1: Profiler Rewrite (`src/systems/profiler.lua`)
- [ ] Hierarchical timers (nested start/stop)
- [ ] Frame accumulator (report every N frames)
- [ ] Memory tracking (`collectgarbage("count")`)
- [ ] Draw call counter, physics body counter
- [ ] On-screen overlay (not just console)
- [ ] JSON export via existing `src/util/json.lua`
- [ ] `profiler.wrap(module, "functionName")` helper
- [ ] `profiler.wrapAll()` — auto-wrap all major update/populate functions
- [ ] Persistent FPS counter (upgrade naive `love.window.setTitle`)

### Step 2: Benchmark Framework (`src/util/benchmark.lua` — NEW)
- [ ] `benchmark.scene(name, setupFn, teardownFn)` — define benchmark scenes
- [ ] `benchmark.run(sceneName, duration)` — run for N seconds, return stats
- [ ] `benchmark.spawnEntities(count, template)` — spawn N entities
- [ ] `benchmark.measure(fn)` — time a single function call
- [ ] `benchmark.compare(scenes, duration)` — compare multiple scenes
- [ ] JSON export of results

### Step 3: Quick CPU Fixes
- [ ] **3A**: Fix `last_color` reference bug in `renderer.lua` — copy by value
- [ ] **3B**: Remove `pcall` from `Enemy:updateProjectiles` — use nil+isDestroyed guard
- [ ] **3C**: Remove/cache `canvas:newImageData()` in `collision.lua` — use constant damage

### Step 4: GPU Fixes
- [ ] **4A**: Reduce shadow shader MAX_LIGHTS from 350 to 32
- [ ] **4B**: Add moonshine dirty flag in `light.lua` (skip if no light changes)
- [ ] **4C**: Guard shockwave canvas ping-pong in `explosion.lua`

### Step 5: Table Allocation Reduction
- [ ] **5A**: Pre-allocate draw entry tables for enemy projectiles
- [ ] **5B**: Batch projectile draw entries outside per-enemy loop
- [ ] **5C**: Use pre-built tables in `fire.populate()`
- [ ] **5D**: Disable exhaust particle sim when rendering is commented out (`rocket.lua`)

### Step 6: Behaviour Tree & AI Optimization
- [ ] Short-circuit BT walk when enemy far from player
- [ ] Add `enemy_active_range` check before walking tree
- [ ] Cache boss raycast callback instead of creating closure each frame

### Step 7: Viewport Culling (if time permits)
- [ ] Skip draw list population for entities outside camera view + margin
- [ ] Quick AABB check before inserting into `dynamic_draw_list`

### Step 8: Benchmark Tests
- [ ] `misc/benchmark-entities.lua` — entity scaling (10→500 enemies), measure FPS/update/draw
- [ ] `misc/benchmark-rendering.lua` — draw list perf (sort cost, table alloc count)
- [ ] `misc/benchmark-collision.lua` — collision throughput (physics bodies scale)

### Step 9: Wiring
- [ ] Add F1 toggle for profiler overlay
- [ ] Add F2 for quick 5-second benchmark
- [ ] Add `/profile`, `/benchmark`, `/spawn` commands to `cmndX.lua`
- [ ] Require profiler in `main.lua` (uncomment)
- [ ] Call `profiler.wrapAll()` after all modules loaded

---

## Files to Modify

| File | Changes |
|------|---------|
| `goal.md` | **THIS FILE** — merged plan + todo |
| `src/systems/profiler.lua` | Complete rewrite |
| `src/util/benchmark.lua` | **NEW** — benchmark framework |
| `src/main.lua` | Wire profiler, add F1/F2 keybinds |
| `src/game/enemy.lua` | Remove pcall, optimize allocs, short-circuit BT |
| `src/lib/graphics/renderer.lua` | Fix color ref bug, reduce shader switches |
| `src/util/collision.lua` | Remove/cache pixel sampling |
| `src/lib/graphics/shadow.lua` | Reduce MAX_LIGHTS, guard unpack |
| `src/systems/light.lua` | Add dirty flag for moonshine |
| `src/systems/explosion.lua` | Guard shockwave ping-pong |
| `src/game/rocket.lua` | Disable exhaust sim when not drawn |
| `src/game/boss.lua` | Cache raycast callback |
| `src/ui/cmndX.lua` | Add `/profile`, `/benchmark`, `/spawn` |
| `misc/benchmark-entities.lua` | **NEW** |
| `misc/benchmark-rendering.lua` | **NEW** |
| `misc/benchmark-collision.lua` | **NEW** |

---

## Verification Checklist

- [ ] Run game — F1 shows profiler overlay with FPS + timing breakdown
- [ ] `/spawn enemies 100` — perf overlay shows per-system breakdown
- [ ] F2 — 5-second benchmark runs, prints JSON results
- [ ] `love ./misc/benchmark-entities` — scaling data output
- [ ] `love ./misc/benchmark-rendering` — draw list timing at various sizes
- [ ] `love ./misc/benchmark-collision` — physics body scaling
- [ ] Before/after FPS comparison with `var.num_enemies = 100`
- [ ] No visual regressions with default 20 enemies
- [ ] `last_color` fix verified: `setColor` calls reduced
- [ ] No crashes from pcall removal: `isDestroyed()` guards work
