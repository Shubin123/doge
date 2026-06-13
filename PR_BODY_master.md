# Consolidate all branches into `master`

This branch resolves **every** local and remote branch (35 unique refs) into a single line off `main`. After this, `git branch -a --merged master` lists all of them — they are safe to delete.

`main` is the canonical, most-advanced line (it carries the big `src/` restructure: flat `src/*.lua` → `src/game/`, `src/lib/`, `src/systems/`, `src/network/`, `src/ui/`, `src/util/`, and `src/shaders_/` → `src/shaders/`). `master` = `main` + the integrations below. Every `src/*.lua` (96 files) parses under LuaJIT 2.1.

## Branches already contained in `main` (no-op — fully merged already)
`bullets/rockets-sorting`, `cars`, `editor`, `extras++`, `ffi-data`, `fixed-normalmaps`, `godmode++`, `improved_camera_1`, `improved-editor`, `js`, `moonshine`, `mult++`, `multiplayer`, `refactored_2`, `settings-saves`, `ui`, `work1` (+ local `testing`).

## Integrated for real (features brought into the tree)
| Branch | What landed |
|---|---|
| `blocks` | `conf.lua` + `multiplayer.lua` content (auto-merged); kept master's `fallback_mode` guard. |
| `grass-improved` | grass opacity/randomization (`systems/grass.lua`). Stale `main.lua`/`conf.lua` hunks resolved to master. |
| `skew-shader` | **new module `src/hit.lua`** (hit/skew effect, 265 lines) — present and available; not yet wired into the restructured `main.lua`. |
| `main_structured` | **new modules `src/systems/indicators.lua`, `src/systems/border.lua`, `src/security/p2p_permissions.lua`, `src/security/sandbox.lua`** — present and available. Its integration hooks were **not** applied because it ships a different network transport (ENet vs master's TCP); engine kept as master's. |

New files added vs old `main`: `src/hit.lua`, `src/systems/indicators.lua`, `src/systems/border.lua`, `src/security/p2p_permissions.lua`, `src/security/sandbox.lua`.

## Recorded only (`-s ours` — merged into history, tree unchanged, nothing lost)
These could not be applied without breaking master's working tree; their commits remain reachable from the merge for later salvage.

| Branch | Why record-only |
|---|---|
| `normalMaps` | Superseded by master's newer normal-map work (already uncommented `isSteveWalk`, did the `offset` cleanup). |
| `walls` | WIP atlas refactor; its `main.lua` loads `gfx/atlas/new_atlas.png` which **does not exist even on its own branch** → would crash. Diverges from master's normal-map atlas. |
| `gpu-sorting` | GPU depth-buffer instance sorting architecturally conflicts with master's CPU y-sort + normal-map shader; taking it would drop normal-map lighting. |
| `improvements++` | Parallel **mod-system architecture** (`engine/mod_system.lua` + `src/mods/**`) that replaces master's monolithic engine. Preserved for deliberate adoption — say the word to pivot to it instead. |
| `god-mode`, `IMP3`, `improv2`, `worlds`, `vfx`, `Refactored`, `hash-map-draw` | Predate the `src/` restructure; edit files that `main` moved/renamed → modify/delete conflicts everywhere. Superseded. |

## Salvageable-but-not-pulled (available in history if wanted)
- `god-mode`: `UniformBuilder.lua`, `UniformSender.lua`
- `IMP3`: 5 new shaders (`enemy_aura/enemy_death/map_transition/sprite_transparency/pixel.frag`), `Character1` art, `.map` files, ~32 map/character modules (need path-porting)
- `worlds`: `area_manager.lua` (needs porting) · `vfx`: `logger.lua`, `config.lua`

## Follow-ups
- Wire up `hit.lua` and `main_structured`'s `indicators`/`border` modules into the restructured engine (detailed resolution recipes available on request).
- Decide whether to adopt `improvements++`'s mod-system architecture (separate effort, not a merge).
- After merging this PR, delete the consolidated branches.
