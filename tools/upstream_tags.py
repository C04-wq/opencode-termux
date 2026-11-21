#!/usr/bin/env python3
"""Resolve the highest stable OpenCode tag from complete git ls-remote output.

git ls-remote returns every matching tag without GitHub REST pagination. For
annotated tags it emits both the tag object and a peeled ^{} commit line; the
peeled commit must win over the tag-object SHA.
"""
from __future__ import annotations

import re
import sys

TAG_PATTERN = re.compile(r"refs/tags/(v[0-9]+[.][0-9]+[.][0-9]+)(\^\{\})?$")
SHA_PATTERN = re.compile(r"[0-9a-f]{40}")


def resolve(payload: str) -> tuple[str, str, str]:
    direct: dict[str, str] = {}
    peeled: dict[str, str] = {}

    for line in payload.splitlines():
        fields = line.split()
        if len(fields) != 2:
            continue
        sha, ref = fields
        match = TAG_PATTERN.fullmatch(ref)
        if match is None or not SHA_PATTERN.fullmatch(sha):
            continue
        tag = match.group(1)
        if match.group(2):
            peeled[tag] = sha
        else:
            direct[tag] = sha

    candidates: list[tuple[tuple[int, int, int], str, str, str]] = []
    for tag, direct_sha in direct.items():
        version = tag[1:]
        sha = peeled.get(tag, direct_sha)
        if not SHA_PATTERN.fullmatch(sha):
            continue
        candidates.append((tuple(map(int, version.split("."))), tag, version, sha))

    if not candidates:
        raise ValueError("No stable official OpenCode x.y.z commit tags were found")

    _, tag, version, sha = max(candidates)
    return tag, version, sha


if __name__ == "__main__":
    try:
        print(*resolve(sys.stdin.read()), sep=" ")
    except ValueError as error:
        raise SystemExit(f"upstream-tags: {error}") from error
