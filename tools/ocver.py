#!/usr/bin/env python3
"""Read pinned versions from tools/supply-chain-lock.json.

The lock file is the single source of truth. Workflows, CI scripts and the
installer must ask this helper instead of repeating a version literal.

    ocver.py current                 -> <version> from the lock
    ocver.py revision                -> <package_revision> from the lock
    ocver.py debversion [version]    -> <version>-<revision>
    ocver.py tag [version]           -> v<version>, or v<version>-<revision> past the first build
    ocver.py field <name> [version]  -> lock["opencode"][version][name]

`version` defaults to the lock's "current" entry. The first build of a
version publishes as `v<version>` and packages as `<version>-1`; a rebuild
of the same upstream version bumps the revision, so the tag and the Debian
version rise together.
"""
import json
import os
import sys
from pathlib import Path

LOCK = Path(os.environ.get("OCVER_LOCK") or Path(__file__).resolve().parent / "supply-chain-lock.json")


def load() -> dict:
    return json.loads(LOCK.read_text(encoding="utf-8"))


def resolve(argv: list[str]) -> str:
    if not argv:
        raise SystemExit(__doc__)
    command, rest = argv[0], argv[1:]
    lock = load()
    revision = int(lock.get("package_revision", 1))

    if command == "current":
        return lock["current"]

    if command == "revision":
        return str(revision)

    if command == "debversion":
        return f"{rest[0] if rest else lock['current']}-{revision}"

    if command == "tag":
        version = rest[0] if rest else lock["current"]
        return f"v{version}" if revision == 1 else f"v{version}-{revision}"

    if command == "field":
        if not rest:
            raise SystemExit("ocver: field needs a name")
        name, tail = rest[0], rest[1:]
        version = tail[0] if tail else lock["current"]
        try:
            value = lock["opencode"][version][name]
        except KeyError:
            raise SystemExit(f"ocver: no {name!r} for opencode {version}")
        return value if isinstance(value, str) else json.dumps(value)

    if command == "bunpty":
        if not rest:
            raise SystemExit("ocver: bunpty needs a field (ref, commit, portable_pty)")
        try:
            return lock["bun_pty"][rest[0]]
        except KeyError:
            raise SystemExit(f"ocver: no bun-pty {rest[0]!r} in the lock")

    raise SystemExit(f"ocver: unknown command {command!r}")


if __name__ == "__main__":
    print(resolve(sys.argv[1:]))
