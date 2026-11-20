#!/usr/bin/env python3
"""Make OpenTUI's Bun asset loader accept Termux's `android` platform.

OpenTUI picks its native library from the Node platform triple:

    getCurrentNodeAssetTarget() -> { platform: process.platform, arch, libc }

On Termux `process.platform` is `"android"`, which has no entry in the asset
descriptor table, so the TUI dies with "Unsupported OpenTUI Node asset target:
android-arm64" before rendering. The native library itself is an ordinary
bionic-arm64 shared object, so the correct mapping is the Linux arm64 one:

    { platform: "linux", arch: "arm64", libc: "musl" }

`libc: "musl"` is only used to pick the `@opentui/core-linux-arm64-musl`
package name; that package is where the build puts the bionic `libopentui.so`,
so the label describes the slot, not the libc the library was linked against.

The same mapping is required in `resolveNativeLibraryPath`, whose Linux branch
is what actually imports the package.

Applied to the installed `@opentui/core` chunks after `bun install`, before
`Bun.build` bundles them.

    patch-opentui-loader.py <opencode-source-tree>
"""

import sys
from pathlib import Path

TARGET = "function getCurrentNodeAssetTarget() {\n"
TARGET_INSERT = (
    "function getCurrentNodeAssetTarget() {\n"
    "  // Termux reports android; the bionic build is the linux-arm64 asset.\n"
    '  if (process.platform === "android") return { platform: "linux", arch: process.arch, libc: "musl" };\n'
)
LINUX_BRANCH = '  if (process.platform === "linux") {\n'
LINUX_BRANCH_NEW = '  if (process.platform === "linux" || process.platform === "android") {\n'


def patch_chunk(path: Path) -> bool | None:
    text = path.read_text(encoding="utf-8")
    if TARGET not in text:
        return None
    changed = False
    if TARGET_INSERT not in text:
        text = text.replace(TARGET, TARGET_INSERT, 1)
        changed = True
    if LINUX_BRANCH_NEW not in text:
        if text.count(LINUX_BRANCH) != 1:
            raise SystemExit(
                f"patch-opentui-loader: {path.name}: expected one linux branch, "
                f"found {text.count(LINUX_BRANCH)}"
            )
        text = text.replace(LINUX_BRANCH, LINUX_BRANCH_NEW, 1)
        changed = True
    if changed:
        path.write_text(text, encoding="utf-8")
    return changed


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-opentui-loader.py SOURCE_ROOT")
    tree = Path(sys.argv[1])
    if not tree.is_dir():
        raise SystemExit(f"patch-opentui-loader: not a directory: {tree}")

    candidates = sorted(tree.glob("**/node_modules/@opentui/core/chunk-bun-*.js"))
    if not candidates:
        raise SystemExit(
            "patch-opentui-loader: no @opentui/core bun chunks found; run bun install first"
        )

    patched, seen = [], 0
    for path in candidates:
        state = patch_chunk(path)
        if state is None:
            continue
        seen += 1
        if state:
            patched.append(path)
    if not seen:
        raise SystemExit(
            "patch-opentui-loader: no getCurrentNodeAssetTarget in @opentui/core chunks"
        )
    for path in patched:
        print(f"patch-opentui-loader: mapped android to linux-arm64 in {path.name}")
    if not patched:
        print(f"patch-opentui-loader: already applied to {seen} chunk(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
