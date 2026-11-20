#!/usr/bin/env python3
"""Make @ff-labs/fff-bun load its bionic build on Termux.

fff ships an `aarch64-linux-android` binary, but `resolveEmbeddedLibPath()`
only names darwin, win32 and linux, so on Termux it returns null and the file
search gives up: `!Fff.available()` then selects the ripgrep layer, which
re-scans the tree with `rg --files` every ten seconds.

The android branch imports the packaged `.so` with `{ type: "file" }`, the same
way the other platforms do, so Bun emits it next to index.js and hands back its
installed path (`publicPath` is the install dir for the android target).

Applied to the installed package after `bun install`, before `Bun.build`.

    patch-fff-android.py <opencode-source-tree>
"""

import sys
from pathlib import Path

ANCHOR = '''  if (process.platform === "win32") {
    return importFile(
      import(`@ff-labs/fff-bin-win32-${process.arch}/fff_c.dll`, {
        with: { type: "file" },
      }),
    );
  }
'''

BRANCH = '''
  if (process.platform === "android") {
    return importFile(
      import(`@ff-labs/fff-bin-android-arm64/libfff_c.so`, {
        with: { type: "file" },
      }),
    );
  }
'''


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-fff-android.py SOURCE_ROOT")
    tree = Path(sys.argv[1])
    if not tree.is_dir():
        raise SystemExit(f"patch-fff-android: not a directory: {tree}")

    candidates = sorted(tree.glob("**/node_modules/@ff-labs/fff-bun/src/embedded.ts"))
    # bun links one package into several node_modules trees; patch the file once.
    unique = sorted({path.resolve() for path in candidates})
    if len(unique) != 1:
        raise SystemExit(
            f"patch-fff-android: expected one @ff-labs/fff-bun/embedded.ts, got {unique}"
        )

    path = unique[0]
    text = path.read_text(encoding="utf-8")
    if 'process.platform === "android"' in text:
        print(f"patch-fff-android: already applied to {path}")
        return 0
    if text.count(ANCHOR) != 1:
        raise SystemExit(
            "patch-fff-android: win32 branch changed upstream; update the anchor"
        )

    path.write_text(text.replace(ANCHOR, ANCHOR + BRANCH, 1), encoding="utf-8")
    print(f"patch-fff-android: enabled the bionic libfff in {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
