#!/usr/bin/env python3
"""Report the largest files in a runtime tar archive without extracting it."""

from __future__ import annotations

import argparse
import tarfile
from pathlib import Path


def inspect_archive(path: Path) -> tuple[int, int, list[tuple[str, int]]]:
    archive_size = path.stat().st_size
    files: list[tuple[str, int]] = []
    total_size = 0

    with tarfile.open(path, mode="r:*") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            size = member.size
            total_size += size
            files.append((member.name, size))

    files.sort(key=lambda item: (-item[1], item[0]))
    return archive_size, total_size, files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--top", type=int, default=20, help="number of largest files to show")
    args = parser.parse_args()

    if args.top < 1:
        parser.error("--top must be at least 1")
    if not args.archive.is_file():
        parser.error(f"archive does not exist: {args.archive}")

    try:
        compressed, expanded, files = inspect_archive(args.archive)
    except (OSError, tarfile.TarError) as error:
        parser.error(f"cannot read archive: {error}")

    mib = 1024 * 1024
    print(f"Archive: {args.archive}")
    print(f"Compressed archive: {compressed:,} bytes ({compressed / mib:.2f} MiB)")
    print(f"Regular-file payload: {expanded:,} bytes ({expanded / mib:.2f} MiB)")
    print(f"Regular files: {len(files)}")
    print(f"\nLargest {min(args.top, len(files))} files:")
    for name, size in files[: args.top]:
        print(f"{size:>14,} bytes  {size / mib:>8.2f} MiB  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
