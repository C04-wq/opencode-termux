#!/usr/bin/env python3
"""Turn upstream's compile-only build into an Android runtime-bundle build.

The release line up to 2.2.6 shipped one compiled ELF. That ELF embeds Bun, the
module graph and every native asset, which makes it ~86 MB compressed and
~244 MiB installed, and it pins the exact Bun release inside the product.

2.2.7 ships the same module graph as plain JavaScript and runs it on Termux's
`bun` package instead:

    $PREFIX/lib/opencode/index.js + hashed assets   (this patcher)
    $PREFIX/lib/opencode/libopentui-*.so            (bionic OpenTUI)
    $PREFIX/lib/opencode/librust_pty_arm64.so       (bionic bun-pty)
    $PREFIX/bin/opencode                            (shell wrapper, execs bun)

Upstream's `Bun.build` call only knows `compile: {...}`. The patch adds an
`android` target that builds a bundle instead:

    * registers `{ os: "linux", arch: "arm64", abi: "android" }` so
      `OPENCODE_TARGET=linux-arm64-android` resolves to exactly one target;
    * swaps `compile` for `outdir` + `publicPath` under
      `OPENCODE_INSTALL_DIR`, so `{ type: "file" }` imports (OpenTUI's
      `libopentui.so`, the app archive, wasm) resolve to absolute paths at
      runtime instead of being embedded in an executable;
    * keeps `bytecode: false` -- bytecode is a compile-time artefact;
    * skips the compiled-artifact gates (`NativeArch.verify`) that assume a
      single executable, and keeps `verifyArtifact` (it only scans file
      contents, which is also valid for a bundle);
    * selects the musl asset names for libc-based native lookups.

Run after `tools/patch-opencode-source.py`; every anchor must match exactly
once so an upstream change fails the build instead of shipping a silently
different product.

    patch-opencode-bundle.py <opencode-source-tree>
"""

import sys
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise SystemExit(
            f"patch-opencode-bundle: expected one anchor in {path.name}, "
            f"found {count}: {old.splitlines()[0]!r}"
        )
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-opencode-bundle.py SOURCE_ROOT")
    root = Path(sys.argv[1])
    build = root / "packages/cli/script/build.ts"
    if not build.is_file():
        raise SystemExit(f"patch-opencode-bundle: missing {build}")

    # copyFile is only needed once the android target copies nothing; keep the
    # import list untouched and place the bundle path purely in JS. The current
    # android target writes no extra file, so no import change is required.

    replace_once(
        build,
        '  abi?: "musl"\n',
        '  abi?: "musl" | "android"\n',
    )
    replace_once(
        build,
        "  { os: \"linux\", arch: \"x64\", abi: \"musl\", avx2: false },\n",
        "  { os: \"linux\", arch: \"x64\", abi: \"musl\", avx2: false },\n"
        '  { os: "linux", arch: "arm64", abi: "android" },\n',
    )
    replace_once(
        build,
        "  const parcelWatcherPackage = `@parcel/watcher-${item.os}-${item.arch}${item.os === \"linux\" ? `-${item.abi ?? \"glibc\"}` : \"\"}`\n",
        # `name` is not defined yet, so only the install dir and the target flag
        # are resolved here; libDir is declared with `name` further down.
        '  const android = item.abi === "android"\n'
        '  const installDir = process.env.OPENCODE_INSTALL_DIR\n'
        "  if (android && !installDir)\n"
        '    throw new Error("OPENCODE_INSTALL_DIR is required for the android target")\n'
        "  const parcelWatcherPackage = `@parcel/watcher-${item.os}-${item.arch}${item.os === \"linux\" ? `-${item.abi ?? \"glibc\"}` : \"\"}`\n",
    )
    replace_once(
        build,
        "        contents: `export default () => require(${JSON.stringify(parcelWatcherPackage)})`,\n",
        # Bun resolves the package name at build time and there is no
        # @parcel/watcher-linux-arm64-android build in that namespace. The
        # bionic module is installed as an asset next to the bundle instead.
        "        contents: android\n"
        "          ? `import { createRequire } from \"node:module\"\\nexport default () => createRequire(import.meta.url)(${JSON.stringify(`${installDir}/watcher.node`)})`\n"
        "          : `export default () => require(${JSON.stringify(parcelWatcherPackage)})`,\n",
    )
    replace_once(
        build,
        "  const target = targetName(item)\n"
        '  const name = target.replace(binary, "cli")\n'
        "  const executablePath = await compileExecutable(item)\n",
        "  const target = targetName(item)\n"
        '  const name = target.replace(binary, "cli")\n'
        '  const libDir = path.join(outdir, name, "lib")\n'
        "  const executablePath = android ? undefined : await compileExecutable(item)\n",
    )
    replace_once(build, "    bytecode: true,\n", "    bytecode: !android,\n")
    replace_once(
        build,
        "    compile: {\n"
        "      autoloadBunfig: false,\n"
        "      autoloadDotenv: false,\n"
        "      autoloadTsconfig: true,\n"
        "      autoloadPackageJson: true,\n"
        "      target: target.replace(binary, \"bun\") as Bun.Build.CompileTarget,\n"
        "      ...(executablePath ? { executablePath } : {}),\n"
        '      outfile: path.join(outdir, name, "bin", binary),\n'
        "      execArgv: [\n"
        '        "--smol",\n'
        "        `--user-agent=opencode/${Script.channel}/${Script.version}/cli`,\n"
        '        "--use-system-ca",\n'
        '        "--no-warnings",\n'
        '        "--",\n'
        "      ],\n"
        "      windows: {},\n"
        "    },\n",
        # publicPath makes the emitted `{ type: "file" }` assets reference their
        # installed absolute path, which is what the runtime loads.
        "    ...(android\n"
        '      ? { target: "bun" as const, outdir: libDir, publicPath: `${installDir}/` }\n'
        "      : {\n"
        "          compile: {\n"
        "            autoloadBunfig: false,\n"
        "            autoloadDotenv: false,\n"
        "            autoloadTsconfig: true,\n"
        "            autoloadPackageJson: true,\n"
        "            target: target.replace(binary, \"bun\") as Bun.Build.CompileTarget,\n"
        "            ...(executablePath ? { executablePath } : {}),\n"
        '            outfile: path.join(outdir, name, "bin", binary),\n'
        "            execArgv: [\n"
        '              "--smol",\n'
        "              `--user-agent=opencode/${Script.channel}/${Script.version}/cli`,\n"
        '              "--use-system-ca",\n'
        '              "--no-warnings",\n'
        '              "--",\n'
        "            ],\n"
        "            windows: {},\n"
        "          },\n"
        "        }),\n",
    )
    replace_once(
        build,
        "      OPENCODE_LIBC: item.os === \"linux\" ? `'${item.abi ?? \"glibc\"}'` : \"undefined\",\n",
        "      OPENCODE_LIBC: item.os === \"linux\" ? `'${android ? \"musl\" : (item.abi ?? \"glibc\")}'` : \"undefined\",\n",
    )
    replace_once(
        build,
        "      FFF_LIBC: item.os === \"linux\" ? `'${item.abi ?? \"gnu\"}'` : \"undefined\",\n",
        "      FFF_LIBC: item.os === \"linux\" ? `'${android ? \"musl\" : (item.abi ?? \"gnu\")}'` : \"undefined\",\n",
    )
    replace_once(
        build,
        '      ...(item.os === "linux" ? { "process.env.OPENTUI_LIBC": JSON.stringify(item.abi ?? "glibc") } : {}),\n',
        '      ...(item.os === "linux"\n'
        '        ? { "process.env.OPENTUI_LIBC": JSON.stringify(android ? "musl" : (item.abi ?? "glibc")) }\n'
        "        : {}),\n",
    )
    replace_once(
        build,
        "  verifySimulationGraph(simulationInputs)\n"
        "  await NativeArch.verify(path.join(outdir, name, \"bin\", item.os === \"win32\" ? `${binary}.exe` : binary), item.arch)\n",
        "  verifySimulationGraph(simulationInputs)\n"
        "  // A bundle has no executable to inspect; the runtime loads the natives\n"
        "  // from the install directory instead.\n"
        "  if (!android)\n"
        "    await NativeArch.verify(path.join(outdir, name, \"bin\", item.os === \"win32\" ? `${binary}.exe` : binary), item.arch)\n",
    )

    print("patch-opencode-bundle: android bundle target installed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
