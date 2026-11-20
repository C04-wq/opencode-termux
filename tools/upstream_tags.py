#!/usr/bin/env python3
"""Resolve the highest stable OpenCode 2.x tag from GitHub matching-refs JSON.

The upstream project maintains separate 1.x and 2.x release lines. The latest
GitHub release endpoint can therefore point at 1.x while this Termux runtime
tracks 2.x. Only direct commit tags matching v2.MAJOR.MINOR are accepted.
"""
from __future__ import annotations

import json
import re
import sys
from typing import Any


TAG_PATTERN = re.compile(r"refs/tags/(v2[.][0-9]+[.][0-9]+)")
SHA_PATTERN = re.compile(r"[0-9a-f]{40}")


def resolve(payload: str) -> tuple[str, str, str]:
    refs: Any = json.loads(payload)
    if not isinstance(refs, list):
        raise ValueError("GitHub matching-refs response must be a JSON array")

    candidates: list[tuple[tuple[int, int, int], str, str, str]] = []
    for item in refs:
        if not isinstance(item, dict):
            continue
        match = TAG_PATTERN.fullmatch(str(item.get("ref", "")))
        if match is None:
            continue
        obj = item.get("object")
        if not isinstance(obj, dict):
            continue
        sha = obj.get("sha", "")
        if obj.get("type") != "commit" or not isinstance(sha, str) or not SHA_PATTERN.fullmatch(sha):
            continue
        tag = match.group(1)
        version = tag[1:]
        candidates.append((tuple(map(int, version.split("."))), tag, version, sha))

    if not candidates:
        raise ValueError("No stable official v2.x.y OpenCode commit tags were found")

    _, tag, version, sha = max(candidates)
    return tag, version, sha


if __name__ == "__main__":
    try:
        print(*resolve(sys.stdin.read()), sep=" ")
    except (json.JSONDecodeError, ValueError) as error:
        raise SystemExit(f"upstream-tags: {error}") from error
