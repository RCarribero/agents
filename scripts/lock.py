"""Cross-platform file locking. POSIX uses fcntl, Windows uses msvcrt."""
from __future__ import annotations

import os
import sys
import time
from contextlib import contextmanager
from pathlib import Path

if sys.platform == "win32":
    import msvcrt

    def _lock(fd, exclusive: bool):
        # msvcrt.locking is advisory; lock 1 byte at offset 0
        while True:
            try:
                msvcrt.locking(fd, msvcrt.LK_LOCK, 1)
                return
            except OSError:
                time.sleep(0.05)

    def _unlock(fd):
        try:
            msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
else:
    import fcntl

    def _lock(fd, exclusive: bool):
        fcntl.flock(fd, fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH)

    def _unlock(fd):
        fcntl.flock(fd, fcntl.LOCK_UN)


@contextmanager
def file_lock(path: str | Path, exclusive: bool = True, timeout_s: float = 10.0):
    """Open a lockfile next to `path` and acquire an exclusive lock.

    Usage:
        with file_lock("session_log.md"):
            append_line(...)
    """
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    lockpath = p.with_suffix(p.suffix + ".lock")
    deadline = time.time() + timeout_s
    fd = os.open(str(lockpath), os.O_RDWR | os.O_CREAT, 0o644)
    try:
        while True:
            try:
                _lock(fd, exclusive)
                break
            except Exception:
                if time.time() > deadline:
                    raise TimeoutError(f"file_lock timeout: {lockpath}")
                time.sleep(0.05)
        yield
    finally:
        try:
            _unlock(fd)
        finally:
            os.close(fd)


def append_atomic(path: str | Path, line: str) -> None:
    """Append a single line to `path` under exclusive lock. Auto-newline."""
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    if not line.endswith("\n"):
        line = line + "\n"
    with file_lock(p):
        with open(p, "a", encoding="utf-8") as f:
            f.write(line)
