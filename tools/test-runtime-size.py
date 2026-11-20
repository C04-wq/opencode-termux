#!/usr/bin/env python3
"""Regression tests for the runtime archive size reporter."""

from __future__ import annotations

import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORTER = ROOT / "tools" / "analyze-runtime-size.py"


def main() -> None:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        archive_path = root / "runtime.tar.gz"
        payload = root / "payload"
        payload.mkdir()
        (payload / "small.txt").write_bytes(b"small")
        (payload / "large.bin").write_bytes(b"x" * 4096)

        with tarfile.open(archive_path, "w:gz") as archive:
            archive.add(payload / "small.txt", arcname="lib/small.txt")
            archive.add(payload / "large.bin", arcname="lib/large.bin")
            archive.add(payload, arcname="lib", recursive=False)

        result = subprocess.run(
            [sys.executable, str(REPORTER), str(archive_path), "--top", "1"],
            check=True,
            capture_output=True,
            text=True,
        )
        assert "Regular files: 2" in result.stdout
        assert "lib/large.bin" in result.stdout
        assert "lib/small.txt" not in result.stdout
        assert "Regular-file payload: 4,101 bytes" in result.stdout

    print("PASS: runtime archive size report lists the largest regular files.")


if __name__ == "__main__":
    main()
