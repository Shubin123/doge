#!/usr/bin/env python3
"""
check_lua51.py -- reject Lua 5.2+/LuaJIT-only syntax in code that has to run
on plain Lua 5.1.

The web build (love.js) embeds vanilla Lua 5.1, while the desktop build runs
LuaJIT. LuaJIT accepts `goto`/`::labels::`, and a system `lua` is usually 5.4+
which accepts even more -- so nothing on a dev machine catches this, and the
first sign of trouble is the wasm build dying with a parse error before it
draws a frame (which is exactly how enemy.lua:695 was found).

Usage: tools/check_lua51.py [root ...]      # default: src
Exits non-zero and lists offenders if anything is found.
"""
import re
import sys
from pathlib import Path

# (pattern, why) -- applied to source with comments and strings blanked out.
CHECKS = [
    (re.compile(r"\bgoto\s+[A-Za-z_]\w*"), "`goto` is Lua 5.2+ / LuaJIT only"),
    (re.compile(r"::\s*[A-Za-z_]\w*\s*::"), "`::label::` is Lua 5.2+ / LuaJIT only"),
    (re.compile(r"(?<![/])//(?![/])"), "`//` integer division is Lua 5.3+"),
    (re.compile(r"[^<>=~]<<|>>[^=]"), "bitwise shift operators are Lua 5.3+"),
    (re.compile(r"\bmath\.(?:type|tointeger|ult)\b"), "math.type/tointeger/ult are Lua 5.3+"),
    # table.unpack/pack are 5.2+, but `unpack or table.unpack` is the standard
    # 5.1-compatible fallback and must not be flagged -- only bare uses are.
    (re.compile(r"(?<!or )\btable\.(?:pack|unpack)\b"), "table.pack/unpack are Lua 5.2+ (use `unpack or table.unpack`)"),
    (re.compile(r"\btable\.move\b"), "table.move is Lua 5.3+"),
]


def strip_noise(src: str) -> str:
    out = list(src)
    i, n = 0, len(src)

    def blank(a, b):
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        c = src[i]
        # long bracket [[ ]] / [=[ ]=] (string or, after --, comment)
        m = re.match(r"--\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            end = src.find(close, i)
            end = n if end == -1 else end + len(close)
            blank(i, end); i = end; continue
        if src.startswith("--", i):
            end = src.find("\n", i)
            end = n if end == -1 else end
            blank(i, end); i = end; continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            end = src.find(close, i)
            end = n if end == -1 else end + len(close)
            blank(i, end); i = end; continue
        if c in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2; continue
                if src[j] == c or src[j] == "\n":
                    j += 1; break
                j += 1
            blank(i, j); i = j; continue
        i += 1
    return "".join(out)


def main(argv):
    roots = [Path(p) for p in (argv[1:] or ["src"])]
    problems = []
    for root in roots:
        for path in sorted(root.rglob("*.lua")):
            src = path.read_text(encoding="utf-8", errors="replace")
            clean = strip_noise(src)
            for pattern, why in CHECKS:
                for m in pattern.finditer(clean):
                    line = clean.count("\n", 0, m.start()) + 1
                    text = src.splitlines()[line - 1].strip()
                    problems.append(f"{path}:{line}: {why}\n    {text}")
    if problems:
        print("Lua 5.1 compatibility problems (these break the web/wasm build):\n")
        print("\n".join(problems))
        print(f"\n{len(problems)} problem(s).")
        return 1
    print(f"Lua 5.1 check: clean ({sum(1 for r in roots for _ in r.rglob('*.lua'))} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
