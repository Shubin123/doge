# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.


## Project Overview

This is a 2D action game built with LÖVE2D featuring real-time global illumination using Jump Flood Algorithm (JFA) and puddle water effects. The game includes combat mechanics, multiplayer support, and a built-in level editor.

## Essential Commands

### Running and Building
```bash
# Run the game in development mode (with hot-reload)
./run.sh

# Build distributable packages (.love file and .app for macOS)
./build.sh

# Extract .love file from executable
./unpack.sh game.exe
```

### Testing
```bash
# GPU regression suite: pixel-exact frames, render-pass counts and frame time
# vs. a baseline revision (exit 0 pass / 1 regression / 2 could not run).
# See tests/gpu/README.md.
python3 tests/gpu/run.py                  # vs. tests/gpu/BASELINE
python3 tests/gpu/run.py --baseline HEAD  # vs. the last commit
python3 tests/gpu/run.py --json           # machine-readable report
python3 tests/gpu/run.py --checks         # functional checks (enemy sprites, death light)

# Test new game systems integration
'/Applications/love.app/Contents/MacOS/love' ./src/test_improvements.lua

# Test module loading and structure
'/Applications/love.app/Contents/MacOS/love' ./src/test_structure.lua
```

### In-Game Debug Keys
- `F1` - Add 1000 currency
- `F2` - Skip to next wave
- `F3` - Spawn random enemy
- `F4` - Spawn powerup
- `z` - Toggle 2x zoom
- `b` - Step bullet tracer / tesla bolt brightness down (`var.tracer_brightness`; wraps to full)
- `escape` - Toggle menu
- `space` - Start game (when integration system is active)

### Console Commands (`/` or `,` opens the console, `ui/command.lua`; Esc closes it)
- `editor.enable` / `editor.disable` - Toggle map editor
- `save` / `load` - Save/load game state
- `reload` - Reload game modules
- `blackhole [x] [y]` - Move the black hole (default: just ahead of you)
- `boss` / `boss spawn [x] [y]` - A bear; `boss arm [x] [y]` - a robot arm (default 200 px ahead); `boss gate` - open the home gate; `boss beat [region|all]` - count a region's boss beaten (its stalls go up)
- `time [hour]` - Show or set the time of day

## Architecture Overview

### Module System
The codebase follows a modular architecture with clear separation of concerns:
- **Entry Point**: `src/main.lua` contains game loop and integrates all systems
- **Global State**: Most modules are loaded as globals in main.lua (e.g., `player`, `enemy`, `gun`)
- **Physics**: Uses LÖVE2D's Box2D integration with `world` as global physics world
- **Rendering**: Custom renderer with dynamic draw list sorting by Y-coordinate

### Shader Pipeline
Multi-pass rendering system for advanced visual effects:
1. Scene renders to canvas
2. JFA generates distance fields using ping-pong buffers
3. Ray marching calculates global illumination
4. Post-processing (bloom, CRT filter) applied

Key shader files:
- `src/shaders/jfa_*.frag` - Jump Flood Algorithm passes
- `src/shaders/raymarching.frag` - Global illumination
- `systems/puddle.lua` - Puddle and pool water (wobbly ellipses on the ground)

### Integration System
The `game.integration` module coordinates all gameplay systems:
- Manages wave progression
- Handles currency and upgrades
- Spawns powerups
- Coordinates enemy deaths with rewards

When modifying gameplay, ensure integration.lua is updated to maintain system cohesion.

### Courtyard
- The home map's ground (`map.map`) is always grass: `game/courtyard.lua` sorts TX Tileset Grass's tiles by what's on them and lays out clumped tufts, flower patches, pebbles and flagstone paths (portal, door, car, east to the black hole) from a fixed seed. It covers -2000..3760 x -2000..2800. Each tile only measures the path segments binned near it, and the result is cached (`cache/courtyard`). Saves don't keep the ground (`map.restore` ignores older saves' `base_tiles`, from before the courtyard).

### Regions & Portal
- `game/regions.lua` lays out four regions (Wasteland, Castle, Neon City, Sanctum) procedurally from fixed seeds, 20000 px apart east of the home map, as a street plan on a 64 px grid: rows of buildings in blocks (corners at the ends, alleys between), each facing a pavement and a road with a pavement and a wall across it (gateways into the yards behind), avenues crossing in line through post-flanked gaps and lined with posts, the main one from the portal's square to a landmark, a square across from the pool. Each region's `layout` table says which sprites play which part (kerb, wall, flank, parked, roadworks, companions...). The ground follows the plan: every cell is lot, pavement, road or square (`r.zones`, one texel per cell: floor layer weights and a shade), blending over ragged edges or, for tiled floors (`ground.hard`), changing at the cell edge. Neon City's pavements and squares are TileSet/grounds.png's dark tiles, each multi-tile piece assembled as drawn, its roads the asphalt plates. Puddles lie in roads and lots, grass in lots (`grass.public.addField`), the pool beside the portal's square.
- Light by height (`SPRITE_SHADER` in regions.lua): region sprites carry their base row and flags in their vertex colour. Tall ones (facades, walls, towers, lamps, glowing signs, props over 96 px) write alpha 1 and block GI; low props write the ground's 0.4 so light passes; `flat` ones (grates, carpets, rubble) are drawn into the ground pass under whoever walks over them. Faces are lit from the ground point under each texel, only from the side they face (`faceShade`), and only by lights that reach it (a light behind a building is stopped by its footprint: see Light & What Stands in Its Way); low props are premultiplied by their alpha by day so the composite's divide leaves them as bright as tall ones.
- Light emitters: sprites with a `glow` entry in `gfx/regions/<id>.lua` (lamps, flames, neon, glowing glass) have their glowing texels in `<id>_glow.png`; those draw at full strength in the dark (and so feed GI their colour), and each emitter adds a transient point light from the ground under it, a coloured pool on the floor and a halo (`regions.drawGlows`, drawn after the sorted sprites). Fire flickers.
- Art: one atlas per region in `gfx/regions/<id>.png`, sprite rects + categories in `gfx/regions/<id>.lua`, ground textures in `<id>_floor.png`. Sprite pools per region are named in `regions.list`.
- Normal maps (`lib/graphics/normalmap.lua`): every standing thing has one, region sprites (not `flat` ones) and the home map's arches, trees, house, car and shop counter. `normalmap.of(image, quads, path, detail)` bakes it on the GPU at load from the art (outline bevelled, brightness as height at three scales: the shape, each texel against its 3x3 with colour edges as grooves, and recesses against the 7x7; each quad on its own, its own relief scaled by `detail`: regions' `RELIEF`, deepest for facades), or uses a hand-drawn `<name>_normal.png` beside the sheet if there is one. `normalmap.GLSL` shades with it in `SPRITE_SHADER` and the object shader (`shadow.lua`, switched on per draw by a drawable's `normal_map`, which the renderer hands to `shadow.setNormals` with its ground line): each light, and the sky's ambient, counts relative to a flat face with the light in front, so flat parts are as bright as before; a light round behind what a texel faces fades out as it passes edge-on (`FACING`), so one behind a face or in line with its foot only catches what's turned toward it. Both shaders light an upright texel from where each light is over the ground (`LIGHT_HEIGHT`, the flashlight's own: `lightHeightOf`) up to where the texel is over its ground line. Characters keep their own (`characterAnimator`).
- `game/portal.lua`: standing in any region's portal opens the travel selector (Up/Down, Enter/E, 1-5, mouse, Esc); `regions.teleport` moves the player and `camera.snap` jumps the camera. The home portal starts sealed (dull red colours, `portal.sealedParams`): standing in it prompts "[E] Summon its guardian" (`bosses.summon`), and it only opens once that boss is beaten (`bosses.isGateOpen`, `portal.opened`). Region portals always work.

### Bosses
- `game/bosses.lua` is the hub. **The gate**: the home portal's guardian is the bear, summoned from the portal's prompt onto clear ground in front of it (`gateSpot`); beating it sets `bosses.gateOpen` for good. **Lairs**: a region with `boss` in `regions.list` (Castle `"bear"`, Neon City `"arm"`) has one at `r.lair` (the junction of the main avenue and the middle street, in front of the landmark; worked out without the layout RNG, so layouts and structure keys don't move). It comes out while you're in that region (`regions.current`) and goes when you leave, back at full health next time; beaten (`bosses.beaten[id]`) it stays beaten. `bosses.cleared(id)`: beaten, or the region has no boss; the region's stalls stand only then. A kill (`bosses.defeated`) leaves its light, a trinket you haven't got (or a medkit) and a medkit. Saves keep the gate and what's beaten (`lairs`; a save without it: sealed, nothing beaten); the snapshot carries them (`lairs`) to clients. `var.region_bosses` (conf.lua) off: no lair bosses, the gate open, every stall up (the GPU harness turns it off).
- Hits: every boss fixture's user data is a part (`{ type = "boss", boss, body, radius, weak, hit }`, `bosses.register`), so `collision.getType` calls it `"boss"`. Bullets and fireballs (`projectile`/`boss`), rockets (`rocket`/`boss`) and their splash (`bosses.blast`, from `rocketSplash`), arrows, the tesla coil (`bosses.parts` as targets), and the black hole gun (stops at one, `bosses.drain`s it) all reach them; a part's `weak` scales the damage. Deaths happen in the boss's own update, never in the physics step.
- The bear (`game/boss.lua`, 200 HP): hops at you and ground-pounds, lasers from its eyes (`laser_damage` per second, you're hurt in ticks of 20); headless at 20% it only hops. Everything hurts you through `player.hurt`.
- The robot arm (`game/robotArm.lua`, 300 HP): a turret bolted to the street, every part a two-bone IK chain (`ik2`: law of cosines). The arm (shoulder, elbow, wrist, then the hand at its pitch) is solved in the upright plane through the base and the claw's target, in ground-plus-height coordinates (`(x, y, z)` draws at `(x, y - z)`, each piece sorts by the ground under it); the claw's two fingers and the base's two gun arms are screen-space chains (`ik2Toward` picks the bend side). Moves: track, slam (ring shown, then stuck in the street with its claw exposed, 3x damage), sweep (a roll goes under it), grab (held and squeezed, then thrown; shoot the claw for 25 to break free), and bolts from the guns (hostile bullets) all along; under half health it's quicker and red. The art is baked into ImageData at load (`robotArm.load`), lit pieces through the object shader and neon added over them (`robotArm.drawPiece`, the renderer's `draw_type = "robotArm"`). Its base is a static body; the bones and claw carry kinematic sensor circles where they're drawn. Clients draw it from the snapshot (`arms`) and solve the IK themselves.

### Minimap
- `ui/minimap.lua`, top left in the HUD (`hud.lua`'s `drawMinimap` frames it), north up with you in the middle: the world's static, non-sensor fixtures (`world:queryBoundingBox`; region glass in blue) over each region's street plan (`r.plan`, a texel per `ZONE` cell, colours in regions.lua's `PLAN`) or the courtyard's grass, with portals, enemies and the car (kept on the edge) marked. Drawn a texel per pixel into a 44 px canvas by `minimap.render()` at the top of `draw.mydraw` (before the frame's other targets have anything to store), scaled up with the HUD. `var.minimap` off hides it (the GPU harness turns it off).

### Black Hole & Time
- `game/blackhole.lua` sits at (1400, 300) east of home (`blackhole [x] [y]` in the console moves it). Near it time slows: `love.update` multiplies `dt` by `blackhole.timeScale` right after networking, so everything after that line runs on slowed time (use `love.timer.getTime()` for real time). It pulls the player, enemies, globs and bullets, swallows what crosses the horizon, and `blackhole.applyLensing()` bends `scene_canvas` before GI. On low graphics (no screen-space passes) a stand-in in the sorted list draws it instead (`blackhole.populate` / `drawFallback`: the tilted disk round the shadow, the photon ring, the lensed arc), and `blackhole.drawSlowTint` turns the frame cold while time is slow. In multiplayer the host sends its position and the shared pace in the snapshot.

### Weapons
- `game/gun.lua` holds the hotbar (1-9, the wheel): pistol, SMG, shotgun, rifle, rocket launcher, tesla coil (`teslaCoil.lua`), bow (`arrows.lua`), fireball, black hole gun. Each has a held model, a 128 px turntable sheet in `gfx/3d/*.dds`; pistol, SMG, shotgun, bow and tesla are modelled in `tools/weapon_models/main.lua` (`tools/weapon_models/build.sh <name>` renders and encodes one). HUD names and 16x16 icons are in `ui/hud.lua`, in hotbar order.
- Black hole gun (slot 9, the portal gun model): `game/blackholeGun.lua`. Each shot flies to the cursor (stopping at a wall or an enemy) and opens a small black hole for a few seconds that drags enemies in and swallows them, and enemies' bullets too, then collapses with a shockwave (`explosion.TYPES.IMPLOSION`). It doesn't slow time or pull the player. Drawn by `blackhole.applySmallLensing` (the black hole's lens shader in blue-violet); on low graphics a plain stand-in. Pulls only where the world runs (host, single player).

### Day & Night
- `systems/daynight.lua` keeps `daynight.hour` (game time, so the black hole slows it; `var.day_length` seconds a day, starting at `var.day_start`). `daynight.apply()` sets `shadow.ambient` (0.2 at night, the old look), which every lit shader reads, characters included; up to `daynight.DAY_AMBIENT` by day; `shader.pass` hands `daynight.daylight()` and `daynight.tint()` to the composite, which by day shows the scene's own colours under the sky. The HUD's clock is in `hud.lua` (`drawClock`); the host's hour goes out in the snapshot and saves keep it. The GPU scenario pins midnight.

### Shops & Safe Zone
- Every shop is data in `game/shops.lua` (edit that, not the code): id, name, region, `at` (`house`, `plaza` = the portal's square, `square` = the market square), `offset`, `hours` (`{ open, close }`, past midnight when close < open, or `"always"`), `stall` awning colours, `keeper` colours, `stock` (`{ item = id, price }`, `{ trinket = id, price }`, `{ fireballs = n, price }`; nine at most with the shelf) and `shelf` (trinkets you haven't got, new each morning at 06:00, priced by `shelfPrice`). `game/shop.lua` checks it at load (`shop.validate`: a typo names the shop and field) and builds each: the house's keeper and counter as before, or a stall (awning on posts, keeper, counter with a lantern and a static fixture) on clear ground near its spot (`clearSpot`: away from region sprites, statics and the portal). Regions keep `r.plaza` and `r.square` for it. A region's stalls only stand once its boss is beaten (`bosses.cleared`): until then `keeperPosition` is nil (no keeper, prompt, light or draw) and the counter's body is inactive (`shop.update` switches it and `nav.forget`s the spot).
- The house is the home shop: inside it (`var.indoors`) `player.isSafe()` is true and every damage path skips the player; its door is too narrow for enemies. Stalls are out in the open. E at a counter opens that shop's panel while it's open (`shop.openAt`); closed, its keeper sleeps. `shop.keypressed` runs before the rest of the game's keys. Saves keep the shelves (`shops`).

### Enemies
- `game/enemy.lua`: each enemy thinks a few times a second (`Enemy:think`, staggered by index; 0.2 s fighting, 0.4 s coming, 1 s far) and between thoughts steers toward the velocity it chose with a force (`AI.STEER`), so knockback impulses still land. With you in sight (one raycast a thought) inside `AI.ENGAGE` it holds its weapon's `range`, circling you (`orbit`, flipped now and then or when stuck), and only then shoots, leading you (`lead`). Out of sight it follows one shared flow field to you (`lib/nav.lua`'s `grid:flow`, rebuilt at most every 0.5 s once you change cell); far off it drifts, further still it waits. A spatial hash built each frame in `enemy.update` keeps them apart. Each enemy's traits come from its index, not the RNG.
- Shots go with animations (`MOVES` in enemy.lua): each look's attack plays its animation once through on the game's clock (`instance.setFrame`), the weapon firing on the frames where the arm or guns are out (`hits`), then it walks again; its cooldown is never shorter than the move. The floating gun has none: its frame turns it to face you and each shot kicks it back. Clients get the pinned frame in the snapshot (`f`).
- Enemy weapons (`game/enemyWeapons.lua`): every hotbar weapon in an enemy version plus their own attacks. Bullets (pistol, SMG, shotgun, rifle, bow, orb; rockets and fireballs carry a `burst` that goes off where they land, via `collision.lua` or the end of their flight), `tesla` (a bolt to you within reach with nothing between), `laser` (beams that charge from the move's start, showing where, then burn; `beams`/`fan` make the multi-laser; walls stop them) and `blackhole` (`blackholeGun.new { hostile = true }`: it flies through enemies, opens on you, pulls you in rather than them, hurts at its heart, drawn in the hot palette). `LOADOUT` gives each look a primary weapon and a special by index (`enemyWeapons.pick`); the special comes on its `CASTS` move (watchman `cast`, frame 7) on its own cooldown, at most `MAX_BEAMS` beams and `MAX_HOLES` holes at once. Beams, bolts and sparks are drawn in one additive batch after the sorted list (`enemyWeapons.draw`), and sent to clients in the snapshot (`enemyFx`). Enemy rockets explode as `explosion.TYPES.BLAST` (no shockwave pass).
- Melee (`MELEE` in enemy.lua): within reach, watchmen punch (frames 5, 10) and mechs spin their blades (19, 27, 45); each hit is a blow (`Enemy:strike`) that lands only if you're still in reach with nothing between, and they press in while swinging. Half of each, by index (`floor(index / 7) % 2 == 1`), are brawlers: they close in to fight this way and don't shoot.
- An enemy slot's sprite (`gun_enemies[index + 2]`) shows only while an enemy holds the slot: `enemy.addEnemy` shows it (typed by index, or as saved), death releases it, `enemy.clear` hides them all. characterAnimator makes every instance a visible princess, so a sprite left out of this stands about like a villager; the only character outside of you and the enemies is the shopkeeper, in the house.
- Health (`enemy.max_health`, 3: a pistol shot is 1): bullets do their weapon's `damage` (`collision.lua`), arrows 1.5, the tesla coil 12/s; rockets, fire, fireballs and the black holes kill. `Enemy:damageEnemy(damage, x, y, kind)` hands what's left to its sprite (`characterAnimator.hurt`): once hurt, its outline is a gauge round it (lit clockwise from the top as far as its health goes, green to yellow to red, dark the rest; white as it's hit, the body flashing too), and a hit with a point leaves a mark where it struck (`characterAnimator.mark`: bullets and arrows a `hole`, rockets, fireballs and the tesla a `scorch`; the last 8 per sprite, in a small texture with a row per instance (`InstanceDamage` carries health, flash, row and count), drawn on its opaque texels only). A slot taken again starts clean (`characterAnimator.clearMarks`). Saves keep `max_health` (an older save's enemies come back unhurt); clients get the health (`h`) in the snapshot, not the marks.
- `lib/nav.lua`: grids over the physics world (cells tested lazily against static fixtures, grown by a clearance), A* paths (`nav:path`, the car's autopilot) and flow fields (`nav:flow`, the enemies).

### Inventory
- `game/inventory.lua`: the bag, two rows of nine slots of item stacks (food among them: apple, bread healing over time, drumstick, glowberries for light, chili for speed via `player.speedBoost`; H eats when there's no bandage) (`inventory.ITEMS`: id -> name, desc, stack, `use()` returning true or false and why, `keep` to not use it up, a 16x16 palette icon). I or Tab opens the panel (arrows/mouse pick, Enter/click use, Q/right-click drop, Esc closes); H uses a bandage or medkit, K the car key. `inventory.add/remove/count/room`, `inventory.place(id, count, x, y)` lays one on the ground, where it slides into the bag when you're near (host and single player only). Enemies leave one now and then (`ENEMY_DROPS`, from `Enemy:damageEnemy`'s death, on their own RNG). The shop sells into it. Saves keep it as `bag` (`inventory.getSaveData` / `restore`; a save without one empties it).

### Trinkets
- `game/trinkets.lua`: passive things, each paying for what it does in light (`gun.useAmmo`, the light bar every weapon spends; without it, nothing happens and the bar flashes red): Mirror Ward (a force field turning enemy shots back at them, 4), Ember Heart (hurt: a ring of fire, 12), Leech Fang (kills heal half a heart while hurt, 3), Lantern Moth (a moth familiar zapping the nearest enemy in sight, 2), Phoenix Feather (cheats a killing blow, back on three hearts in a blaze, 80, then rests 90 s), Static Soles (a roll ends in a shock, 6). Hooks: `player.hurt` asks `trinkets.onHurt` first, `Enemy:damageEnemy`'s death calls `trinkets.onKill`; rings and blazes go off in `trinkets.update`, out of the physics step.
- They're bag items (registered into `inventory.ITEMS` with `trinket`, one to a slot) and work while in the bag and equipped (`slot.on ~= false`; Enter toggles it, `trinkets.toggle`; the bag frames equipped ones in gold, the save keeps `on`). The shop shelves two you haven't got (`trinkets.shopItems`, restocked each morning); enemies drop one rarely (`TRINKET_DROP`). The HUD shows the equipped ones over the light bar, three to a row (`trinkets.drawHUD`).
- `var.equip_all_trinkets` (conf.lua, on for play-testing) puts every trinket in the bag, equipped, at every start and load (`trinkets.equipAll`). The GPU harness turns it off.

### Car
- `game/car.lua`: the parked car is drivable. Near it an arrow and "[E] Drive" show over it (`car.drawUI`); E gets in (`car.enter`: the player's body becomes the car's, wider, faster and coasting; `player.inCar` hides the princess and stops shooting and dodging), E again gets out beside it (`car.exit`). Host and single player only. The car key (inventory item `car_key`, lying in front of the car while nobody has it, `car.keySpot`) calls it: K or using it runs `car.summon`, and the car drives itself to you (`car.update`'s autopilot: A* on a 32 px grid over the world's static fixtures, cells tested lazily and grown by the car's size, the path straightened, re-planned as you move or after backing off when held up) and parks 72 px from you; K again stops it. Saves keep a self-driving car parked. It's never far (`keepClose`): once you're `TOO_FAR` from it (or past the screen's corner), it's put on clear ground just off the screen, the fewest steps it could drive to you from (`nav`'s flow field, `Field:stepsAt`), behind you, not behind anything tall, in water, a portal or by the black hole; a key still lying by it comes too.

### Light & What Stands in Its Way
- Footprints: where each standing thing meets the ground, as segments (`shadow.eachFoot`): region sprites', the arch's and the tree's (`lib/graphics/footprint.lua`: each column's lowest opaque texel, followed while it's gentle, so canopies, lamp arms and arch openings don't count; closed into a shape as deep as its collision, `item.feet` / `arch.feet` / `tree.feet`, glass excepted), the house's walls down their middles (`house.feet`, the door open) and the parked car's body. One the light's owner stands inside is skipped. Characters don't block light.
- No light shines through them. Each frame `shadow.update` draws the reach map (`REACH_SHADER`, one small pass): a row per light, how far it gets in each of 512 directions before a footprint. Every lit shader (the object shader, regions' ground and sprite shaders, puddles, characters) leaves a light out of a point beyond that (`shadow.REACH_GLSL`'s `reaches`), testing the point's ground: the texel itself on the ground, for an upright thing the ground under it pushed `FACE_GAP` out from its foot the way it faces (`faceGround`: the foot is on its own footprint's edge, so a light in line with it only grazed it, and flickered), a character's feet. A light's row rides in its range (`w = range + row * 8192`; `lightRange` decodes it), so tiled draws' subsets keep it. A new lit shader includes `REACH_GLSL`, decodes ranges with `lightRange` and multiplies each light by `reaches(...)`; `shadow.sendLights` sends the rest.
- `systems/light.lua`, the flashlight: it points along `gun.heading`, the way you're going, or the cursor's while you stand still (`gun.currentVel` turns toward it by angle; `gun.lastAimDirection` is the cursor's, for the weapons). It's held in your hand, `light.HEIGHT` over its ground, which is at your feet under the body (pulled back short of a footprint between, as close behind a wall). A pool on the ground (`light.drawBeam`) and point lights strung along it (`light.update`) run out from there, the lights striking upright things from the hand's height (`shadow.setBeam`'s height), and a glow at the gun in the air over them (`light.renderLights`). The pool and the glow are dark per pixel wherever the line from its ground crosses a footprint (`SHADOW_SHADER`, the 64 nearest ahead; the glow tested at the ground below it, its `lift`), the lights fade out against what's in the way (an average over rays across its middle), and those lights (`beam` transient lights) go by the flashlight's line of sight rather than the reach map (`shadow.setBeam`, `beamReaches`), so they don't land in a pillar's shadow.

### Destruction
- `game/destruction.lua`: every region sprite with collision (buildings, walls, towers, landmarks, lamps, barriers, props; `regions.lua`'s `place` registers each as it lays a region out, keyed `<region>:<n>` by its place in the layout) and the home map's arch (`destruction.forArch`, from `map.addMapToDynamicDrawList`) is a structure, with health from its size and region (`MATERIAL`; glass far less). The house (the shop, the safe zone), the tree and the car aren't.
- Hits come in through `util/collision.lua` (`shotStructure`: bullets `BULLET` x their damage, enemies' `HOSTILE`, fireballs `FIRE`; `rocketSplash` calls `destruction.blast`) and `arrows.lua`. Host and single player only; the snapshot carries `destruction.getNetworkData()` (what's down, the last half second's hits) to clients, which replay the hits for the marks and bring down what the host says.
- A hit marks its face about chest height up from where it struck the footprint: bullet holes, scorches, cracks, one multiply-blended mesh per structure (`DECAL_SHADER`, clipped to the sprite's opaque texels, so the scene's alpha and the GI's walls are untouched). The sprite is cut into shards (a jittered grid split along diagonals, one pattern per sprite shared by every copy); cracks run along their edges, loose shards on the outline come away, the top crumbles as health passes `CRUMBLE`, a blast knocks a hole through, and whatever no longer rests on the ground through its neighbours falls. A broken structure draws its remaining shards (`fmesh`) instead of its quad.
- At no health (`pending`, brought down in `destruction.update` after the physics step) it `takeDown`s: its fixture, draw list entry, footprint (light passes) and lamp go, `nav.forget` clears the enemies' and the car's grids there, and every shard falls with dust. Shards are drawn with the region sprite shader (`regions.useLook`), their height in their vertex colour; at rest they're `flat` rubble drawn with the ground (`destruction.drawRubble`, oldest dropped past `MAX_RUBBLE`). Saves keep what's down (`structures`); a load puts the rest back up unhurt (`putBack`).

### Saves, Settings & Cache
All in LÖVE's save directory (`love.filesystem`, identity `doge`), each in its own file:
- `util/serial.lua`: saves are `*.sav` (quicksave and the menu's slots) and hold game state only. Every serial function refuses a name that isn't a plain `*.sav`, so a save can never land on the settings or the cache. Every launch and restart ends `love.load` with `serial.loadMostRecent()` (newest by modtime that loads; host and single player only); New Game calls `serial.startFresh()` first, a `fresh_start` marker that the next load consumes instead.
- `util/settings.lua`: the Settings screen's choices in `settings.json`. The screen has three tabs (`ui/menu.lua`): Video (resolution as `var.window_width/height`, fullscreen, v-sync, frame cap `var.fps_cap` paced in `draw.limitFrame`, GUI scale `var.gui_scale` read by `skin.guiScale`, show FPS, minimap `var.minimap`), Graphics (a Low/Medium/High preset, `settings.PRESETS`, over: graphics, lighting, max lights `var.max_lights` capping `shadow.update`'s lights, shadows `var.light_shadows` (the reach map and the flashlight's footprints), normal maps `var.normal_maps` (off sends `normalmap.flat()`), grass, puddles, lamp glows) and Effects (CRT, bloom, shockwaves, tracers, screen shake, particles, rocket splash). `settings.load()` runs at the top of `love.load`, before the window opens; the menu calls `settings.save()` after every click on the Settings screen, and `love.quit` writes any changed elsewhere (`settings.saveIfChanged()`). Values that don't fit are skipped, and loading a save never touches these. To persist a new setting, add it to `FIELDS` there.
- `util/cache.lua`: `cache/` holds slow load-time results keyed by an md5 of what they're worked out from (`cache.key`; a big file goes in as `cache.stamp(path)`, its size and modtime, rather than hashed): the courtyard's tile layout (keyed by `game/courtyard.lua` and its sheet), the sprite atlas as LZ4 (unpacks about six times faster than the shipped zlib), each region's grass (`grass-<id>`: the fields' vertex data; region grass grows from its own seeded generator, `regions.lua`'s `grassKey`/`packGrass`), decoded PNGs (`cache.imageData` / `cache.newImage`: the region atlases and glow maps, the princess's normals, the explosion sheet) and the sounds' mono mixes (`audio.lua`). All desktop only; the browser works them out every time. A changed input just recomputes it; deleting `cache/` is always safe. A warm launch's `love.load` takes about 290 ms (806 ms without them).

### Global Variables
Key globals defined in main.lua:
- `world` - Physics world
- `enemies_bods` - Enemy physics bodies array
- `dynamic_draw_list` - Rendering order list
- `var` - Configuration variables from config/var.lua

### State Management
- Game states: "menu", "running", "game"
- Check state with `var.State`
- Integration system activates when `var.State ~= "menu"`

### System Responsibilities
**IMPORTANT**: Maintain clear separation of concerns between systems:
- **fire.lua**: Only handles fireball visual effects and fire damage - NO knockback
- **gun.lua/bullet systems**: Handle all projectile knockback and impact physics
- **enemy.lua**: Manages enemy-specific knockback responses and health
- **integration.lua**: Coordinates cross-system interactions

When adding features, ensure they're implemented in the correct system to avoid nil value errors and architectural conflicts.

## Development Notes

### Hot Reload
Lurker automatically reloads changed Lua files. On file change, the game restarts via `love.event.push("quit", "restart")`.

### Adding New Features
1. Create module in appropriate directory (`game/`, `systems/`, `ui/`)
2. Require in main.lua as global or local
3. Add initialization in `love.load()`
4. Add update calls in `love.update(dt)`
5. Add rendering in `love.draw()` respecting draw order
6. Update integration.lua if feature affects gameplay

### Shader Development
- Shaders auto-reload on file change
- Use `shader.prepass()` and `shader.pass()` for global illumination
- All shaders expect specific canvas formats (rgba8, rg16f, r16f)

### Performance Considerations
- Global illumination sample count affects FPS (16-32 for gameplay, 64+ for screenshots)
- Dynamic draw list sorting happens every frame
- Enemy AI updates can be throttled for large enemy counts


### Your Desired understandings:
- dont bother running tests for work, let the user complete that and return if desired, to save tokens. ie: Avoid "Test that..." within planning.