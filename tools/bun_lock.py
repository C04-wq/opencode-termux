"""Parser for Bun lockfiles, which allow trailing commas."""
from __future__ import annotations
import json
from pathlib import Path
from typing import Any


def strip_trailing_commas(source: str) -> str:
    output: list[str] = []
    quoted = False
    escaped = False
    index = 0
    while index < len(source):
        char = source[index]
        if quoted:
            output.append(char)
            if escaped:
                escaped = False
            elif char == chr(92):
                escaped = True
            elif char == chr(34):
                quoted = False
            index += 1
            continue
        if char == chr(34):
            quoted = True
            output.append(char)
            index += 1
            continue
        if char == ",":
            lookahead = index + 1
            while lookahead < len(source) and source[lookahead].isspace():
                lookahead += 1
            if lookahead < len(source) and source[lookahead] in "}]":
                index += 1
                continue
        output.append(char)
        index += 1
    return "".join(output)


def load_bun_lock(path: str | Path) -> dict[str, Any]:
    text = Path(path).read_text(encoding="utf-8")
    try:
        value = json.loads(strip_trailing_commas(text))
    except json.JSONDecodeError as error:
        raise ValueError(f"Invalid Bun lockfile {path}: {error}") from error
    if not isinstance(value, dict) or not isinstance(value.get("workspaces"), dict):
        raise ValueError(f"Invalid Bun lockfile {path}: missing workspaces object")
    return value
