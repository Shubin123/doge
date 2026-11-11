"""Shared fixtures for the atlas pipeline tests."""
import os
import shutil

import pytest


@pytest.fixture(scope="session")
def lua():
    """A real Lua interpreter: $LUA, or the first on PATH (Debian calls it
    lua5.4, Homebrew just lua). Without one, the tests that need it skip."""
    for name in (os.environ.get("LUA"), "lua5.4", "lua5.5", "lua5.3", "lua"):
        path = name and shutil.which(name)
        if path:
            return path
    pytest.skip("no Lua interpreter (set $LUA, or install lua5.4 / brew install lua)")
