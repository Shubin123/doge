#!/usr/bin/env python3
"""GPU regression suite: render the same scripted play-through with a baseline
revision and with the working tree, then compare.

    python3 tests/gpu/run.py                  # vs. the pinned baseline (tests/gpu/BASELINE)
    python3 tests/gpu/run.py --baseline HEAD  # "did my uncommitted change regress?"
    python3 tests/gpu/run.py --json           # one JSON report on stdout, for tools/CI

Checks:
  pixels       every captured frame must match the baseline bit-for-bit
               (loosen with --max-diff / --max-changed)
  passes       per frame, render passes and the pixels they cover must not
               exceed the baseline's
  counters     canvas switches, draw calls, shader switches and texture memory
               (love.graphics.getStats, averaged over the timed frames) likewise
  timing       median frame time under load (frames back to back, one wait
               for the GPU per batch) must not be more than --perf-tolerance
               slower than the baseline's; per-frame render time (draw + wait
               for the GPU) is reported alongside
  determinism  each tree must render identical frames in every round

See tests/gpu/README.md.

Exit status: 0 pass, 1 regression, 2 could not run (no LOVE, bad revision...).
Standard library only; needs git and LOVE 11.x (found via --love, $LOVE, the
macOS app bundle, or `love` on PATH).
"""

import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
HERE = Path(__file__).resolve().parent
HARNESS = HERE / "harness"
BASELINE_FILE = HERE / "BASELINE"

# Counters from love.graphics.getStats() that measure GPU work. Lower is better;
# the candidate may not exceed the baseline (averaged over the timed frames).
WORK_COUNTERS = ("canvasswitches", "drawcalls", "shaderswitches", "texturememory")


class SetupError(Exception):
    pass


# --------------------------------------------------------------------------
# Locating tools
# --------------------------------------------------------------------------
def find_love(explicit):
    # An explicit --love or $LOVE is used or rejected, never silently replaced.
    chosen = explicit or os.environ.get("LOVE")
    candidates = [chosen] if chosen else ["/Applications/love.app/Contents/MacOS/love", shutil.which("love")]
    for c in candidates:
        if c and Path(c).is_file() and os.access(c, os.X_OK):
            return c
    if chosen:
        raise SetupError("LOVE binary %r does not exist or is not executable" % chosen)
    raise SetupError("LOVE binary not found; pass --love /path/to/love or set $LOVE")


def git(*args, binary=False):
    proc = subprocess.run(["git", *args], cwd=ROOT, capture_output=True)
    if proc.returncode != 0:
        raise SetupError("git %s failed: %s" % (" ".join(args), proc.stderr.decode().strip()))
    return proc.stdout if binary else proc.stdout.decode()


def default_baseline():
    if BASELINE_FILE.exists():
        for line in BASELINE_FILE.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                return line
    return "HEAD"


# --------------------------------------------------------------------------
# Assembling a game directory for one tree
# --------------------------------------------------------------------------
def _link(target, link):
    """Symlink, except for individual .lua files, which are copied: the game's
    hot-reloader (src/util/lurker.lua) scans every .lua file it can see with
    love.filesystem.getInfo(path, "file"), which is nil for a symlink."""
    link.parent.mkdir(parents=True, exist_ok=True)
    if str(link).endswith(".lua") and Path(target).is_file():
        shutil.copy(target, link)
    else:
        os.symlink(target, link)


def build_game_dir(dest, rev):
    """Lay out src/ as of `rev` (None = working tree) in `dest`, with the
    harness swapped in for main.lua/conf.lua.

    Nothing is copied wholesale: unchanged files and directories are symlinked
    to the working tree, and only files that differ from `rev` are written
    out of git. LOVE follows symlinks by default.
    """
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)

    if rev is None:
        for entry in SRC.iterdir():
            _link(entry, dest / entry.name)
    else:
        changed = set(p[len("src/"):] for p in
                      git("diff", "--name-only", "-z", rev, "--", "src").split("\0") if p)
        untracked = set(p[len("src/"):] for p in
                        git("ls-files", "--others", "--exclude-standard", "-z", "--", "src").split("\0") if p)
        dirty = set()
        for p in changed | untracked:
            parts = p.split("/")
            for i in range(len(parts)):
                dirty.add("/".join(parts[:i]))

        linked = set()
        for p in git("ls-tree", "-r", "-z", "--name-only", rev, "--", "src").split("\0"):
            if not p:
                continue
            rel = p[len("src/"):]
            parts = rel.split("/")
            clean_dir = next(("/".join(parts[:i]) for i in range(1, len(parts))
                              if "/".join(parts[:i]) not in dirty), None)
            if clean_dir is not None:
                if clean_dir not in linked:
                    _link(SRC / clean_dir, dest / clean_dir)
                    linked.add(clean_dir)
            elif rel in changed or not (SRC / rel).exists():
                out = dest / rel
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(git("show", "%s:%s" % (rev, p), binary=True))
            else:
                _link(SRC / rel, dest / rel)

    for name, alias in (("main.lua", "__game_main.lua"), ("conf.lua", "__game_conf.lua")):
        (dest / name).rename(dest / alias)
    shutil.copy(HARNESS / "main.lua", dest / "main.lua")
    shutil.copy(HARNESS / "conf.lua", dest / "conf.lua")
    _link(HARNESS, dest / "__gpu_harness")


# --------------------------------------------------------------------------
# Running LOVE
# --------------------------------------------------------------------------
def run_love(love, game_dir, out_dir, label, args, extra_env=None):
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    env = dict(os.environ,
               DOGE_GPU_OUT=str(out_dir),
               DOGE_GPU_W=str(args.width),
               DOGE_GPU_H=str(args.height),
               DOGE_GPU_PERF_FRAMES=str(args.perf_frames),
               DOGE_GPU_LABEL=label)
    env.update(extra_env or {})
    started = time.time()
    try:
        proc = subprocess.run([love, str(game_dir)], env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=args.timeout)
        output, code = proc.stdout.decode(errors="replace"), proc.returncode
    except subprocess.TimeoutExpired as e:
        output, code = (e.stdout or b"").decode(errors="replace"), "timeout"
    (out_dir / "love.log").write_text(output)

    results_path = out_dir / "results.json"
    results = json.loads(results_path.read_text()) if results_path.exists() else {}
    results["exit_code"] = code
    results["wall_s"] = round(time.time() - started, 2)
    if not results.get("ok"):
        tail = "\n".join(output.strip().splitlines()[-25:])
        results.setdefault("error", "LOVE exited with %s before finishing" % code)
        results["log_tail"] = tail
    return results


# --------------------------------------------------------------------------
# Pixel comparison (raw RGBA8 dumps written by the harness)
# --------------------------------------------------------------------------
def write_png(path, width, height, rgb_rows):
    raw = b"".join(b"\x00" + row for row in rgb_rows)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 6))
                     + chunk(b"IEND", b""))


def compare_frame(base_dir, cand_dir, name, width, height, heatmap_path):
    a = (base_dir / (name + ".rgba")).read_bytes()
    b = (cand_dir / (name + ".rgba")).read_bytes()
    if len(a) != len(b) or len(a) != width * height * 4:
        return {"identical": False, "error": "frame size mismatch (%d vs %d bytes)" % (len(a), len(b))}
    if a == b:
        return {"identical": True, "max_diff": 0, "changed_fraction": 0.0, "mean_abs_diff": 0.0}

    # Alpha is ignored: the window's alpha channel is never shown.
    per_pixel = [0] * (width * height)
    total = 0
    for c in range(3):
        for i, (x, y) in enumerate(zip(a[c::4], b[c::4])):
            d = x - y if x > y else y - x
            if d:
                total += d
                if d > per_pixel[i]:
                    per_pixel[i] = d
    changed = sum(1 for d in per_pixel if d)
    max_diff = max(per_pixel)

    # Heatmap: unchanged pixels show the baseline frame dimmed, changed ones in
    # red scaled so even a 1/255 difference is clearly visible.
    rows = []
    for yy in range(height):
        row = bytearray()
        for xx in range(width):
            i = yy * width + xx
            d = per_pixel[i]
            if d:
                row += bytes((min(255, 96 + d * 16), 0, 0))
            else:
                p = i * 4
                row += bytes((a[p] // 4, a[p + 1] // 4, a[p + 2] // 4))
        rows.append(bytes(row))
    write_png(heatmap_path, width, height, rows)

    return {
        "identical": False,
        "max_diff": max_diff,
        "changed_pixels": changed,
        "changed_fraction": changed / float(width * height),
        "mean_abs_diff": total / float(width * height * 3),
        "heatmap": str(heatmap_path),
    }


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--baseline", default=None,
                   help="git revision to compare against (default: tests/gpu/BASELINE, else HEAD)")
    p.add_argument("--love", default=None, help="path to the LOVE 11.x binary")
    p.add_argument("--out", default=str(ROOT / "dist" / "gpu-test"),
                   help="artifact directory (frames, heatmaps, logs, report.json)")
    p.add_argument("--width", type=int, default=800)
    p.add_argument("--height", type=int, default=600)
    p.add_argument("--rounds", type=int, default=2,
                   help="alternating baseline/candidate runs (default 2). Timing takes each "
                        "tree's best round; every extra round also re-checks determinism")
    p.add_argument("--perf-frames", type=int, default=240,
                   help="timed frames per run; 0 skips the timing check")
    p.add_argument("--perf-tolerance", type=float, default=0.10,
                   help="allowed median frame-time-under-load slowdown vs. baseline (0.10 = 10%%)")
    p.add_argument("--max-diff", type=int, default=0,
                   help="largest allowed per-channel difference, 0-255 (default 0: bit-exact)")
    p.add_argument("--max-changed", type=float, default=0.0,
                   help="largest allowed fraction of changed pixels per frame (default 0)")
    p.add_argument("--timeout", type=int, default=300, help="seconds per LOVE run")
    p.add_argument("--checks", action="store_true",
                   help="instead: run the functional checks in tests/gpu/checks/ against the "
                        "working tree alone (no baseline, pixel diff or timing)")
    p.add_argument("--passes", metavar="FRAME",
                   help="also list every render pass of FRAME (a capture name, or 'all') for both "
                        "trees: target, size, draw calls and the line of code that set it")
    p.add_argument("--json", action="store_true", help="print only the JSON report on stdout")
    return p.parse_args(argv)


def pass_table(passes):
    return ["    %-8s %5dx%-5d %4d draws  %s" % (p["target"], p["w"], p["h"], p["draws"], p["from"])
            for p in passes or []]


def finish(report, out, args, say):
    (out / "report.json").write_text(json.dumps(report, indent=2))
    if args.json:
        print(json.dumps(report, indent=2))
    code = {"pass": 0, "fail": 1}.get(report["status"], 2)
    if not args.json and report["status"] == "error":
        say("error: %s" % report["error"])
        if report.get("log_tail"):
            say(report["log_tail"])
    return code


def run_checks(love, out, args, say):
    """Each tests/gpu/checks/*.lua is a scenario script that plays the real game
    and reports results with h.check(name, ok, detail)."""
    game = out / "game-candidate"
    build_game_dir(game, None)
    report = {"status": "pass", "checks": [], "failures": []}
    for script in sorted((HERE / "checks").glob("*.lua")):
        name = script.stem
        say("checking %s ..." % name)
        r = run_love(love, game, out / ("checks-" + name), "checks-" + name, args,
                     extra_env={"DOGE_GPU_SCENARIO": str(script), "DOGE_GPU_PERF_FRAMES": "0"})
        if not r.get("ok"):
            return finish({"status": "error", "error": "%s did not finish: %s" % (name, r.get("error")),
                           "log_tail": r.get("log_tail")}, out, args, say)
        if not r.get("checks"):
            report["failures"].append("%s: reported no checks" % name)
        for c in r.get("checks", []):
            c["script"] = name
            report["checks"].append(c)
            if not c["ok"]:
                report["failures"].append("%s: %s%s" % (name, c["name"],
                                          (" -- " + c["detail"]) if c.get("detail") else ""))
    report["status"] = "fail" if report["failures"] else "pass"
    if not args.json:
        for c in report["checks"]:
            say("  %-4s %s: %s" % ("ok" if c["ok"] else "FAIL", c["script"], c["name"]))
            if c.get("detail"):
                say("       " + c["detail"])
        say("%s  (report: %s)" % (report["status"].upper(), out / "report.json"))
    return finish(report, out, args, say)


def main(argv=None):
    args = parse_args(argv)
    say = (lambda *a: print(*a, file=sys.stderr)) if args.json else print
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)

    if args.checks:
        try:
            love = find_love(args.love)
        except SetupError as e:
            return finish({"status": "error", "error": str(e)}, out, args, say)
        return run_checks(love, out, args, say)

    try:
        love = find_love(args.love)
        rev_name = args.baseline or default_baseline()
        rev = git("rev-parse", "--verify", rev_name + "^{commit}").strip()
        say("baseline %s (%s), candidate = working tree" % (rev_name, rev[:10]))
        build_game_dir(out / "game-baseline", rev)
        build_game_dir(out / "game-candidate", None)
    except SetupError as e:
        return finish({"status": "error", "error": str(e)}, out, args, say)

    # Alternate trees so drift in clocks/thermals over the run hits both alike.
    runs = {"baseline": [], "candidate": []}
    for rnd in range(1, max(1, args.rounds) + 1):
        for tree in ("baseline", "candidate"):
            label = tree if rnd == 1 else "%s-%d" % (tree, rnd)
            say("rendering %s ..." % label)
            r = run_love(love, out / ("game-" + tree), out / label, label, args)
            if not r.get("ok"):
                return finish({"status": "error", "error": "%s run failed: %s" % (label, r.get("error")),
                               "log_tail": r.get("log_tail"), "run": r}, out, args, say)
            r["dir"] = out / label
            runs[tree].append(r)

    base, cand = runs["baseline"][0], runs["candidate"][0]
    failures = []

    # Determinism: a tree must render the same frames every round, or a
    # baseline/candidate difference would not mean anything.
    for tree, rs in runs.items():
        for r in rs[1:]:
            for name in rs[0]["order"]:
                a = (rs[0]["dir"] / (name + ".rgba")).read_bytes()
                b = (r["dir"] / (name + ".rgba")).read_bytes()
                if a != b:
                    failures.append("%s is nondeterministic: frame %s differs between rounds" % (tree, name))

    # Pixels and passes, per captured frame
    frames = {}
    for name in base["order"]:
        if name not in cand["captures"]:
            failures.append("frame %s: missing from candidate" % name)
            continue
        info = base["captures"][name]
        r = compare_frame(base["dir"], cand["dir"], name, info["width"], info["height"],
                          out / ("diff-%s.png" % name))
        if r.get("error"):
            failures.append("frame %s: %s" % (name, r["error"]))
        elif r["max_diff"] > args.max_diff or r["changed_fraction"] > args.max_changed:
            failures.append("frame %s: %d pixels differ (max diff %d/255), see %s"
                            % (name, r["changed_pixels"], r["max_diff"], r["heatmap"]))
        bt, ct = info.get("trace") or {}, cand["captures"][name].get("trace") or {}
        for key in ("pass_count", "pass_pixels"):
            r[key] = {"baseline": bt.get(key), "candidate": ct.get(key)}
            if bt.get(key) is not None and ct.get(key, 0) > bt[key]:
                failures.append("frame %s: %s went up: %d -> %d" % (name, key, bt[key], ct[key]))
        if args.passes in (name, "all"):
            r["passes"] = {"baseline": bt.get("passes"), "candidate": ct.get("passes")}
        frames[name] = r

    # GPU work counters and timing
    perf = {}
    if args.perf_frames > 0:
        bp, cp = base["perf"], cand["perf"]
        for key in WORK_COUNTERS:
            b, c = bp["stats_avg"].get(key, 0), cp["stats_avg"].get(key, 0)
            perf[key] = {"baseline": b, "candidate": c}
            if c > b + 0.5:
                failures.append("%s went up: %.1f -> %.1f per frame" % (key, b, c))
        for key in ("render_ms_median", "frame_ms_median"):
            if all(key in r["perf"] for rs in runs.values() for r in rs):
                best = {tree: min(r["perf"][key] for r in rs) for tree, rs in runs.items()}
                b, c = best["baseline"], best["candidate"]
                perf[key] = {"baseline": b, "candidate": c, "speedup": (b / c) if c else None,
                             "rounds": {t: [r["perf"][key] for r in rs] for t, rs in runs.items()}}
        perf["update_ms_median"] = {"baseline": bp["update_ms_median"], "candidate": cp["update_ms_median"]}
        # The gate is the frame's cost under load. Per-frame render time waits
        # on the GPU every frame, which lets it clock down, so taking GPU work
        # out can read slower there; it is reported, and gates only when the
        # harness that ran had no load timing.
        gate = perf.get("frame_ms_median") or perf["render_ms_median"]
        b, c = gate["baseline"], gate["candidate"]
        if c > b * (1 + args.perf_tolerance):
            failures.append("%s regressed: %.3f -> %.3f ms median (> %d%% slower)"
                            % ("frame time under load" if "frame_ms_median" in perf else "render time",
                               b, c, round(args.perf_tolerance * 100)))

    report = {
        "status": "fail" if failures else "pass",
        "failures": failures,
        "baseline": {"rev": rev, "name": rev_name},
        "renderer": cand.get("renderer"),
        "window": cand.get("window"),
        "frames": frames,
        "perf": perf,
        "artifacts": str(out),
    }

    if not args.json:
        r = report["renderer"] or {}
        say("renderer: %s %s (%s)" % (r.get("device"), r.get("version"), r.get("name")))
        say("  %-16s %-26s %15s %21s" % ("frame", "pixels vs baseline", "passes", "pass pixels (M)"))
        for name, fr in frames.items():
            state = "identical" if fr.get("identical") else (
                fr.get("error") or "%d px differ, max %d/255" % (fr["changed_pixels"], fr["max_diff"]))
            pc, pp = fr["pass_count"], fr["pass_pixels"]
            say("  %-16s %-26s %6s -> %-6s %9.2f -> %-9.2f" % (
                name, state, pc["baseline"], pc["candidate"],
                (pp["baseline"] or 0) / 1e6, (pp["candidate"] or 0) / 1e6))
        for key in WORK_COUNTERS:
            if key in perf:
                say("  %-16s %12.1f -> %12.1f per frame" % (key, perf[key]["baseline"], perf[key]["candidate"]))
        for key, label in (("render_ms_median", "render median"), ("frame_ms_median", "under load")):
            if key in perf:
                m = perf[key]
                say("  %-16s %9.3f ms -> %9.3f ms  (x%.2f)" % (label, m["baseline"], m["candidate"],
                                                              m["speedup"] or 0))
        for name, fr in frames.items():
            for tree in ("baseline", "candidate") if "passes" in fr else ():
                say("passes of %s, %s:" % (name, tree))
                for line in pass_table(fr["passes"][tree]):
                    say(line)
        for f in failures:
            say("FAIL " + f)
        say("%s  (report: %s)" % (report["status"].upper(), out / "report.json"))
    return finish(report, out, args, say)


if __name__ == "__main__":
    sys.exit(main())
