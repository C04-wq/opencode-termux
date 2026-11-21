#!/usr/bin/env python3
"""Select the locally compiled FFF C ABI package for the Android target.

The package folder is populated by scripts/ci/build-fff-android.sh from the
exact FFF source commit pinned in tools/supply-chain-lock.json. No prebuilt
Android FFF binary from npm is shipped.
"""
import argparse
from pathlib import Path

ANCHOR = '''  if (process.platform === "win32") {
    return importFile(
      import(`@ff-labs/fff-bin-win32-${process.arch}/fff_c.dll`, {
        with: { type: "file" },
      }),
    );
  }
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tree", type=Path)
    parser.add_argument("--target-arch", choices=("aarch64", "x86_64"), required=True)
    args = parser.parse_args()
    tree = args.tree
    if not tree.is_dir():
        raise SystemExit(f"patch-fff-android: not a directory: {tree}")

    node_arch, package_arch = {
        "aarch64": ("arm64", "arm64"),
        "x86_64": ("x64", "x64"),
    }[args.target_arch]
    package_name = f"@ff-labs/fff-bin-android-{package_arch}"
    branch = f'''
  if (process.platform === "android" && process.arch === "{node_arch}") {{
    return importFile(
      import("{package_name}/libfff_c.so", {{
        with: {{ type: "file" }},
      }}),
    );
  }}
'''

    candidates = sorted(tree.glob("**/node_modules/@ff-labs/fff-bun/src/embedded.ts"))
    unique = sorted({path.resolve() for path in candidates})
    if len(unique) != 1:
        raise SystemExit(
            f"patch-fff-android: expected one @ff-labs/fff-bun/embedded.ts, got {unique}"
        )

    path = unique[0]
    text = path.read_text(encoding="utf-8")
    marker = f'process.platform === "android" && process.arch === "{node_arch}"'
    if marker in text:
        if package_name not in text:
            raise SystemExit("patch-fff-android: Android package branch points to an unexpected package")
        print(f"patch-fff-android: already applied for {args.target_arch}")
        return 0
    if text.count(ANCHOR) != 1:
        raise SystemExit(
            "patch-fff-android: win32 branch changed upstream; update the anchor"
        )

    path.write_text(text.replace(ANCHOR, ANCHOR + branch, 1), encoding="utf-8")
    print(f"patch-fff-android: selected compiled {package_name} for {args.target_arch}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
