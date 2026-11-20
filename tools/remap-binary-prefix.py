#!/usr/bin/env python3
"""Replace an embedded absolute build prefix without changing file size."""

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("file", type=Path)
    parser.add_argument("old_prefix")
    parser.add_argument("new_prefix")
    args = parser.parse_args()

    old = args.old_prefix.encode("utf-8")
    new = args.new_prefix.encode("utf-8")
    if not old.startswith(b"/") or not new.startswith(b"/"):
        raise SystemExit("remap-binary-prefix: prefixes must be absolute paths")
    if len(new) > len(old):
        raise SystemExit("remap-binary-prefix: new prefix is longer than old prefix")
    if b"\x00" in old or b"\x00" in new:
        raise SystemExit("remap-binary-prefix: NUL is not allowed in prefixes")

    data = args.file.read_bytes()
    count = data.count(old)
    if count == 0:
        raise SystemExit("remap-binary-prefix: expected build prefix was not found")

    # Repeated slashes are valid path separators on Android/Linux. Padding with
    # them preserves every byte offset and any suffix following the prefix.
    replacement = new + b"/" * (len(old) - len(new))
    remapped = data.replace(old, replacement)
    if len(remapped) != len(data) or old in remapped:
        raise SystemExit("remap-binary-prefix: postcondition failed")
    args.file.write_bytes(remapped)
    print(f"remap-binary-prefix: replaced {count} occurrence(s), size unchanged")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
