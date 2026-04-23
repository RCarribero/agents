#!/usr/bin/env python3
"""install_hooks.py — symlink/copy our hooks into .git/hooks."""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "scripts" / "hooks" / "pre-commit"
DST = ROOT / ".git" / "hooks" / "pre-commit"

if not SRC.exists():
    print("missing source hook:", SRC, file=sys.stderr)
    sys.exit(1)
DST.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(SRC, DST)
try:
    os.chmod(DST, 0o755)
except Exception:
    pass
print(f"installed: {DST}")
