"""pytest entry point for the GPU regression suite (tests/gpu/run.py).

Renders the scripted play-through with the pinned baseline revision and with
the working tree, and fails on any pixel difference, more GPU work (passes,
pass pixels, canvas switches, draw calls, shader switches, texture memory) or
a slower median frame. Skipped when no LOVE binary is available.

    pytest tests/test_gpu_regression.py -s    # -s shows the report
"""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent / "gpu"))
import run as gpu_run  # noqa: E402


def _love_available():
    try:
        gpu_run.find_love(None)
        return True
    except gpu_run.SetupError:
        return False


@pytest.mark.skipif(not _love_available(), reason="LOVE 11.x not found (set $LOVE)")
def test_gpu_regression(tmp_path, capsys):
    code = gpu_run.main(["--json", "--out", str(tmp_path)])
    report = json.loads(capsys.readouterr().out)
    print(json.dumps({k: report.get(k) for k in ("status", "failures", "perf")}, indent=2))
    assert code == 0, report.get("failures") or report.get("error")
