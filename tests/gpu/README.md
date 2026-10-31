# GPU regression suite

Renders one scripted play-through of the real game twice, once from a
baseline git revision and once from the working tree, then checks that
the candidate:

| check | rule |
|---|---|
| **pixels** | every captured frame matches the baseline bit-for-bit |
| **passes** | per frame, no more render passes and no more pixels covered by them |
| **counters** | per frame on average, no more canvas switches, draw calls, shader switches or texture memory (`love.graphics.getStats`) |
| **timing** | median frame render time (draw plus waiting for the GPU) is at most 10% slower |
| **determinism** | each tree renders identical frames every round, so a difference always means a real change |

## Run it

```sh
python3 tests/gpu/run.py                  # vs. the pinned baseline (tests/gpu/BASELINE)
python3 tests/gpu/run.py --baseline HEAD  # did my uncommitted change regress anything?
python3 tests/gpu/run.py --json           # one JSON report on stdout (for tools/CI)
python3 tests/gpu/run.py --passes default # also list every render pass of a frame
npm run test:gpu                          # same as the first line
pytest tests/test_gpu_regression.py -s    # same, as a pytest test (skips without LOVE)
```

It needs Python 3 (standard library only), git, and LOVE 11.x. The runner
finds LOVE through `--love`, `$LOVE`, `/Applications/love.app`, or `love` on
`PATH`. A run takes about 30 seconds and briefly opens the game window four
times: two rounds, each rendering baseline then candidate.

Exit status: **0** pass, **1** regression, **2** could not run (no LOVE, bad
revision, or the game crashed; `report.json` has the log tail).

## Functional checks

```sh
python3 tests/gpu/run.py --checks         # or: npm run test:gpu:checks
DOGE_GPU_SEED=7 python3 tests/gpu/run.py --checks   # another random world
```

`--checks` plays each script in `checks/` against the working tree alone,
with no baseline, pixel diff or timing. Each script asserts things about the
running game with `h.check(name, ok, detail)`. The run fails if any check
fails or a script crashes.

`checks/enemy_death.lua` covers enemy sprites and the death light. It runs
through zoom changes, screen shake, and with the player far from the world
origin (where camera offsets are large):

- Every frame, every live enemy's sprite must sit exactly on its physics
  body, on screen or off, and every enemy on screen must be treated as on
  screen (that's when it gets turned to face the player).
- For each of 8 kills, it renders the game's own sprite pass and death-light
  pass in isolation with the real camera transform. The light must exist,
  cover the sprite to within 0.25 px, and the sprite must be on the body.
- Every remaining enemy is killed (most of them off screen). Each must fade
  where it died, then be released.
- In a full frame, the death light must show up at the enemy.

Run against the code from before these fixes, every check failed:
sprites up to 3,240 px off their bodies, enemies right of the screen's centre
treated as off-screen (the culling box was centred on the top-left corner),
the light 8 px off during screen shake, off-screen kills fading thousands of
px away, and a dark enemy whose death light added nothing to the frame.

## Output

The runner prints a summary table, writes `dist/gpu-test/report.json`, and
keeps every artifact under `dist/gpu-test/` (change this with `--out`):

- `baseline/*.png` and `candidate/*.png` hold the captured frames.
- `diff-<frame>.png` holds a heatmap of the frames that differ: changed
  pixels in red, everything else as a dimmed copy of the baseline.
- `*/results.json` holds each run's per-frame stats and pass traces, perf
  numbers and renderer info.
- `*/love.log` holds the game's stdout.

Tolerances can be loosened when needed: `--max-diff N` (per channel, 0-255),
`--max-changed F` (fraction of pixels), and `--perf-tolerance F`.

## How it works

`run.py` lays out a game directory per tree. Unchanged files are symlinked
to `src/`, and only files that differ from the baseline are written out of
git. In each directory the harness in `harness/` replaces `main.lua` and
`conf.lua`. The game's own copies of those two files become `__game_main.lua`
and `__game_conf.lua`, and the harness loads them unchanged. Only `love.run`
is replaced, by a fixed-timestep driver (`harness/harness.lua`) that pins
everything that would make two runs differ:

- the RNG is seeded before any game module is required (the grass texture is
  random at require time);
- `love.timer.getTime` returns simulated time;
- the mouse and keyboard are stubbed to a fixed aim, with nothing pressed;
- window events are ignored, and vsync is off.

`harness/scenarios.lua` is the play-through itself. Each `h.capture(name)`
saves one frame and its pass trace. Add a capture whenever you add a render
path. Use only game APIs that the baseline revision also has, because the
same script runs against both trees. Extra fields passed to an older API are
ignored, which is how the bullet captures pass each gun's tracer colours.

To render a one-off scene while working on a look, put a script of the same
shape somewhere and set `DOGE_GPU_SCENARIO=/abs/path/to/it.lua`. The harness
runs it instead of `scenarios.lua`.

The pass trace wraps `love.graphics.setCanvas` for the captured frame. Each
render target change is recorded with the draw calls that landed on it and
the `file:line` that set it, so `--passes` shows exactly where a frame's GPU
time goes.

## Updating the baseline

`BASELINE` pins the revision to compare against. When a visual change is
intended, check the `diff-*.png` heatmaps, then bump `BASELINE` to the commit
that made the change.

## Things this suite has caught

- **Render-pass boundaries change rounding on rgba4 targets.** On Apple GPUs
  (and likely other tile-based ones), draws blended into the rgba4
  `scene_canvas` round differently depending on where its render pass is
  split. Removing a canvas switch that "does nothing" moved a few hundred
  pixels by one rgba4 step (1/15). GI amplified that at silhouettes, to as
  much as 34/255 on screen. `light.skipChain` keeps the pass boundary for
  this reason.
- **Randomness at require time.** Seeding in `love.load` was too late; the
  grass differed between identical runs.
- **Fewer canvases, slower frames.** Letting all moonshine glow chains share
  one set of scratch canvases kept every frame bit-identical and saved 11.5 MB
  of VRAM. It also made the median frame about 1.3 ms slower, because each
  chain then has to wait for the previous one to finish with the shared
  canvases. The timing check caught it, and the change was dropped.
