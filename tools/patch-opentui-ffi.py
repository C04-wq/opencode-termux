#!/usr/bin/env python3
"""Keep Android top-byte pointers intact in OpenTUI's Bun FFI shim.

On some Android/Termux builds bionic hands out heap pointers whose top byte
carries a tag (top-byte-ignore tagging, e.g. 0xb4000075ac80a000 for a mapping
at 0x75ac400000). The address itself stays in the low 48 bits; only the tag
byte is extra.

OpenTUI converts native pointers to JS numbers (`toSafeNumberPointer`) and
rejects anything above Number.MAX_SAFE_INTEGER, so every tagged pointer looks
unsafe and the TUI dies at ot_context_create with "Pointer exceeds safe
integer range" before drawing a single frame.

Clearing the tag is not an option: bionic's Scudo allocator re-checks the tag
in free(), so a masked pointer (tag 0x00 for a 0xb4 allocation) aborts at
teardown with "Pointer tag for 0x... was truncated". Bun 1.4's FFI accepts a
BigInt for `ptr` arguments and passes all 64 bits through to native code, so
the fix is to hand tagged pointers over unchanged:

  * `toSafeNumberPointer` returns the BigInt when it exceeds the safe range
    (untagged pointers keep returning a plain Number, so every other platform
    and every small allocation behaves exactly as upstream);
  * `toBunPointer2` stops wrapping the pointer in Number(); bun.toArrayBuffer
    takes a BigInt too.

`POINTER_UNSAFE` remains for the node:ffi backend, which cannot represent
tagged 64-bit pointers at all.

    patch-opentui-ffi.py <opencode-source-tree>
"""

import argparse
import re
from pathlib import Path

# BigInt.asUintN(64, p) is the identity for the 0..2^64-1 range the checks
# above already enforce, and it is far too rare to appear anywhere else in the
# bundle -- which makes it the marker the build greps for in the compiled ELF:
# minification drops comments but never a global property access.
TOKEN = "BigInt.asUintN(64, "
LEGACY_MASK = "0x00ffffffffffffffn"
FUNC = re.compile(r"function toSafeNumberPointer\((?P<arg>[A-Za-z_$][\w$]*)\)")
BUN2 = re.compile(r"function toBunPointer2\((?P<arg>[A-Za-z_$][\w$]*)\)")
UNSAFE_HEAD = r"if \(%s > BigInt\(Number\.MAX_SAFE_INTEGER\)\) \{"
UNSAFE_THROW = "throw new Error(POINTER_UNSAFE);"


def _tagged_return(arg: str, indent: str) -> str:
    return (
        f"{indent}// Bionic tags heap pointers in the top byte; Scudo free()\n"
        f"{indent}// rejects a cleared tag, so pass the BigInt through untouched.\n"
        f"{indent}return {TOKEN}{arg});\n"
    )


def _strip_legacy_mask(text: str, arg: str) -> tuple[str, bool]:
    """Drop the `ptr &= 0x00ffffffffffffffn` line older releases inserted."""
    pattern = re.compile(rf"^[ \t]*{re.escape(arg)} &= {LEGACY_MASK};\r?\n", re.MULTILINE)
    return pattern.subn("", text)


def patch_number_pointer(path: Path, text: str) -> tuple[str, bool]:
    match = FUNC.search(text)
    if not match:
        raise SystemExit(
            f"patch-opentui-ffi: {path.name}: no toSafeNumberPointer shim found"
        )
    arg = match.group("arg")

    text, stripped = _strip_legacy_mask(text, arg)
    patched_return = f"return {TOKEN}{arg});"
    unsafe = re.search(UNSAFE_HEAD % re.escape(arg), text[match.end() :])
    if not unsafe:
        raise SystemExit(
            f"patch-opentui-ffi: {path.name}: toSafeNumberPointer found without "
            "its unsafe-integer check; upstream changed the shim"
        )

    check_at = match.end() + unsafe.end()
    tail = text[check_at : check_at + 400]
    for statement in (patched_return, f"return {arg};", UNSAFE_THROW):
        offset = tail.find(statement)
        if offset < 0 or offset > 200:
            continue
        line_start = text.rfind("\n", 0, check_at + offset) + 1
        indent = text[line_start : check_at + offset]
        if indent.strip():
            raise SystemExit(
                f"patch-opentui-ffi: {path.name}: unexpected text before "
                f"{statement}"
            )
        if statement == patched_return:
            return text, stripped
        end = check_at + offset + len(statement)
        rest = text[end:]
        if rest.startswith("\r\n"):
            rest = rest[2:]
        elif rest.startswith("\n"):
            rest = rest[1:]
        return text[:line_start] + _tagged_return(arg, indent) + rest, True
    raise SystemExit(
        f"patch-opentui-ffi: {path.name}: unsafe-integer check has no "
        f"{UNSAFE_THROW} to replace; upstream changed the shim"
    )


def patch_array_buffer_pointer(path: Path, text: str) -> tuple[str, bool]:
    match = BUN2.search(text)
    if not match:
        # Older OpenTUI builds have no second backend; nothing to do.
        return text, False
    arg = match.group("arg")
    body_start = match.end()
    body = text[body_start : body_start + 400]
    truncate = f'return typeof {arg} === "bigint" ? Number({arg}) : {arg};'
    keep = f"return {arg};"
    if keep in body:
        return text, False
    if truncate not in body:
        raise SystemExit(
            f"patch-opentui-ffi: {path.name}: toBunPointer2 body changed upstream"
        )
    return text.replace(truncate, keep, 1), True


def patch_file(path: Path) -> bool | None:
    """Return True when patched, False when already patched, None without a shim."""
    text = path.read_text(encoding="utf-8")
    if not FUNC.search(text):
        return None

    text, changed_pointers = patch_number_pointer(path, text)
    text, changed_buffer = patch_array_buffer_pointer(path, text)
    if changed_pointers or changed_buffer:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tree", type=Path, help="OpenCode source tree")
    args = parser.parse_args()
    if not args.tree.is_dir():
        raise SystemExit(f"patch-opentui-ffi: not a directory: {args.tree}")

    candidates = sorted(args.tree.glob("**/node_modules/@opentui/core/chunk-*.js"))
    if not candidates:
        raise SystemExit(
            "patch-opentui-ffi: no @opentui/core chunks found; run bun install first"
        )

    patched, seen = [], 0
    for path in candidates:
        state = patch_file(path)
        if state is None:
            continue
        seen += 1
        if state:
            patched.append(path)
    if not seen:
        raise SystemExit(
            "patch-opentui-ffi: no toSafeNumberPointer shim in @opentui/core chunks"
        )

    for path in patched:
        print(f"patch-opentui-ffi: kept tagged BigInt pointers intact in {path.name}")
    if not patched:
        print(f"patch-opentui-ffi: already applied to {seen} chunk(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
