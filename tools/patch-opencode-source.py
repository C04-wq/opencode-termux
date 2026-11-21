#!/usr/bin/env python3
"""Patch pinned OpenCode source for the verified Android/Bionic release.

The source is fetched at the commit recorded in the supply-chain lock before
this script runs. Each replacement must match exactly once so upstream changes
fail the build instead of silently dropping a safety patch.
"""

import json
import os
import sys
from pathlib import Path

LOCK = Path(__file__).resolve().parent / "supply-chain-lock.json"


def lock_bun_version(root: Path) -> str:
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    return lock["opencode"][lock["current"]]["bun_version"]


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected one build anchor in {path}, found {count}: {old!r}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-opencode-source.py SOURCE_ROOT")
    root = Path(sys.argv[1])
    package = root / "package.json"
    metadata = json.loads(package.read_text(encoding="utf-8"))
    declared = metadata.get("packageManager") or ""
    if not declared.startswith("bun@") or declared.count(".") != 2:
        raise SystemExit(f"unexpected packageManager: {declared!r}")
    # Upstream bumps this every release; rewrite it to the Bun that actually
    # compiles this build instead of pinning a literal here.
    pinned_bun = os.environ.get("OPENCODE_BUN_VERSION") or lock_bun_version(root)
    replace_once(package, f'"packageManager": "{declared}"', f'"packageManager": "bun@{pinned_bun}"')

    build = root / "packages/cli/script/build.ts"
    replace_once(
        build,
        "async function compileExecutable(item: (typeof allTargets)[number]) {\n",
        "async function compileExecutable(item: (typeof allTargets)[number]) {\n"
        ' const pinned = process.env.BUN_SOURCE_TARGET_ELF\n'
        ' if (pinned) {\n'
        '   if (item.os !== "linux" || item.arch !== "arm64" || item.abi) throw new Error("unexpected source-build target " + item.os + "-" + item.arch + (item.abi ? "-" + item.abi : "") + " (set OPENCODE_TARGET=linux-arm64)")\n'
        '   if (!(await Bun.file(pinned).exists())) throw new Error("pinned Bun target missing")\n'
        '   return pinned\n'
        ' }\n',
    )

    # Bionic has no glibc pty helper: for a cross arm64 build upstream resolves
    # @opencode/pty-linux-arm64-gnu and embeds that binary. It cannot exec on
    # Android. build.ts already emits "export default undefined" when the asset
    # is missing, so resolve it only when host and target agree.
    replace_once(
        build,
        "  const opencodePty = await resolveOpencodePty({\n"
        "    platform: item.os,\n"
        "    arch: item.arch,\n"
        '    ...(item.os === "linux" ? { libc: item.abi ?? "glibc" } : {}),\n'
        "  })\n",
        "  const opencodePty: Awaited<ReturnType<typeof resolveOpencodePty>> =\n"
        '    item.os === process.platform && item.arch === process.arch && item.abi !== "android"\n'
        "      ? await resolveOpencodePty({\n"
        "          platform: item.os,\n"
        "          arch: item.arch,\n"
        '          ...(item.os === "linux" ? { libc: item.abi ?? "glibc" } : {}),\n'
        "        })\n"
        "      : undefined\n",
    )

    # Termux reports process.platform "android" for a bionic userspace that has
    # inotify, but upstream only names linux here, so recursive watch silently
    # loses its backend. The @parcel/watcher binary itself is a normal bionic
    # ARM64/x86_64 modules are selected by OPENCODE_PARCEL_WATCHER_PATH, so only the
    # backend name needs to cover android.
    watcher = root / "packages/core/src/filesystem/watcher.ts"
    replace_once(
        watcher,
        '  if (process.platform === "linux") return "inotify"\n',
        '  if (process.platform === "linux" || process.platform === "android") return "inotify"\n',
    )

    # Android exposes the same per-process /proc metadata used by the
    # official Linux foreground-process detector. Keep that upstream behavior
    # on Termux instead of silently disabling terminal process titles.
    daemon_service = root / "packages/process-daemon/src/service.rs"
    service_text = daemon_service.read_text(encoding="utf-8")
    linux_gate = '#[cfg(target_os = "linux")]'
    android_gate = '#[cfg(any(target_os = "linux", target_os = "android"))]'
    if linux_gate in service_text:
        service_text = service_text.replace(linux_gate, android_gate)
    elif android_gate not in service_text:
        raise SystemExit("patch-opencode-source: process-daemon Linux cfg anchors changed")
    fallback_gate = '#[cfg(not(any(windows, target_os = "linux")))]'
    android_fallback = '#[cfg(not(any(windows, target_os = "linux", target_os = "android")))]'
    if fallback_gate in service_text:
        service_text = service_text.replace(fallback_gate, android_fallback)
    elif android_fallback not in service_text:
        raise SystemExit("patch-opencode-source: process-daemon foreground fallback cfg changed")
    daemon_service.write_text(service_text, encoding="utf-8")

    # The CLI aliases `update` to `upgrade`; the TUI's /update calls Updater.apply.
    # Keep the native installer in their shared service so both paths use it.
    updater = root / "packages/cli/src/services/updater.ts"
    replace_once(
        updater,
        '  readonly latest: (method?: Method) => Effect.Effect<string, Error>\n',
        '  readonly latest: (method?: Method) => Effect.Effect<string, Error>\n'
        '  readonly current: () => Effect.Effect<string>\n',
    )
    replace_once(
        updater,
        '  return Service.of({ run, check, apply, method, managed, latest, upgrade, removal })\n',
        '  return Service.of({ run, check, apply, method, managed, latest, current: () => Ref.get(installedVersion), upgrade, removal })\n',
    )
    replace_once(
        updater,
        'export const methods = ["curl", "npm", "pnpm", "bun", "yarn", "vp", "brew", "winget"] as const\n',
        'export const methods = ["curl", "npm", "pnpm", "bun", "yarn", "vp", "brew", "winget", "apt"] as const\n',
    )
    replace_once(updater, '  winget: "WinGet",\n', '  winget: "WinGet",\n  apt: "APT",\n')
    replace_once(
        updater,
        '  const curlBinary = yield* fs.realPath(curlPath).pipe(Effect.orElseSucceed(() => curlPath))\n',
        '  const curlBinary = yield* fs.realPath(curlPath).pipe(Effect.orElseSucceed(() => curlPath))\n'
        '  const termuxPath = path.join(global.home, ".local", "bin", "opencode")\n'
        '  const termuxBinary = yield* fs.realPath(termuxPath).pipe(Effect.orElseSucceed(() => termuxPath))\n'
        '  const prefixLauncher = process.env.PREFIX === undefined ? undefined : path.join(process.env.PREFIX, "bin", "opencode")\n'
        '  const nativeTermux = launcher === termuxPath || executable === termuxBinary || (prefixLauncher !== undefined && (launcher === prefixLauncher || executable === prefixLauncher))\n'
        '  if (nativeTermux) {\n'
        '    const releaseMarker = process.env.PREFIX === undefined ? undefined : path.join(process.env.PREFIX, "lib", "opencode-termux", ".opencode-termux-release-tag")\n'
        '    const installedReleaseTag = releaseMarker === undefined ? "" : yield* fs.readFileString(releaseMarker).pipe(Effect.orElseSucceed(() => ""))\n'
        '    const match = installedReleaseTag.trim().match(/^v(\\d+\\.\\d+\\.\\d+)(?:-([1-9]\\d*))?$/)\n'
        '    const current = match ? `${match[1]}-termux.${match[2] ?? "0"}` : `${OPENCODE_VERSION}-termux.0`\n'
        '    yield* Ref.set(installedVersion, current)\n'
        '  }\n',
    )
    replace_once(
        updater,
        '    if (executable === curlBinary) return "curl"\n',
        '    if (executable === curlBinary) return "curl"\n'
        '    if (nativeTermux) return "curl"\n'
        '    const prefix = process.env.PREFIX\n'
        '    if (prefix && executable === path.join(prefix, "bin", "opencode")) {\n'
        '      const owner = yield* exec(["dpkg-query", "-S", executable]).pipe(Effect.orElseSucceed(() => undefined))\n'
        '      if (owner?.code === 0 && owner.stdout.split("\\n").includes(`opencode: ${executable}`)) return "apt"\n'
        '    }\n',
    )
    replace_once(
        updater,
        '    if (method === "winget") return ["winget", "uninstall", ...wingetArgs]\n',
        '    if (method === "winget") return ["winget", "uninstall", ...wingetArgs]\n'
        '    if (method === "apt") return ["apt-get", "remove", "--yes", "opencode"]\n',
    )
    replace_once(
        updater,
        '  const latest = (selected?: Method) =>\n',
        '  const termuxLatest = Effect.tryPromise({\n'
        '    try: async (signal) => {\n'
        '      const response = await fetch("https://raw.githubusercontent.com/C04-wq/opencode-termux/main/release-checksums.json", {\n'
        '        signal: AbortSignal.any([signal, AbortSignal.timeout(10_000)]),\n'
        '        headers: { Accept: "application/json", "Cache-Control": "no-cache" },\n'
        '      })\n'
        '      if (!response.ok) throw new Error(`Runtime metadata returned HTTP ${response.status}`)\n'
        '      const data: { version?: string; sourceRepo?: string; sourceTag?: string; releaseTag?: string; runtimeId?: string; archiveSha256?: string; archiveSha256X86_64?: string; archiveNameX86_64?: string } = await response.json()\n'
        '      const version = data.version\n'
        '      const checksum = process.arch === "arm64" ? data.archiveSha256 : process.arch === "x64" ? data.archiveSha256X86_64 : undefined\n'
        '      const expectedArchive = "opencode-" + version + (process.arch === "arm64" ? "-android-aarch64-bundle.tar.gz" : "-android-x86_64-bundle.tar.gz")\n'
        '      const releaseTag = data.releaseTag ?? ""\n'
        '      const releaseTagOK = /^v[0-9]+\\.[0-9]+\\.[0-9]+(?:-[1-9][0-9]*)?$/.test(releaseTag) && (releaseTag === "v" + version || releaseTag.startsWith("v" + version + "-"))\n'
        '      const archiveNameOK = process.arch === "arm64" || data.archiveNameX86_64 === expectedArchive\n'
        '      if (!version || !/^\\d+\\.\\d+\\.\\d+$/.test(version) || data.sourceRepo !== "C04-wq/opencode-termux" || data.sourceTag !== "v" + version || !releaseTagOK || data.runtimeId !== "android-bionic-bun-v1" || !checksum || !/^[a-f0-9]{64}$/.test(checksum) || !archiveNameOK) throw new Error("Runtime metadata does not identify a complete, verified Termux release for this architecture")\n'
        '      const revision = releaseTag === "v" + version ? "0" : releaseTag.slice(("v" + version + "-").length)\n'
        '      return `${version}-termux.${revision}`\n'
        '    },\n'
        '    catch: (cause) => new Error(`Could not check native Termux releases: ${errorDetail(cause)}`),\n'
        '  })\n'
        '  const latest = (selected?: Method) =>\n',
    )
    replace_once(
        updater,
        '  const latest = (selected?: Method) =>\n'
        '    (selected ? Effect.succeed(selected) : method()).pipe(\n'
        '      Effect.flatMap((method) =>\n'
        '        method === "winget" ? wingetVersion() : release(method).pipe(Effect.map((data) => data.version)),\n'
        '      ),\n'
        '    )\n',
        '  const latest = (selected?: Method) =>\n'
        '    (selected ? Effect.succeed(selected) : method()).pipe(\n'
        '      Effect.flatMap((detected) =>\n'
        '        nativeTermux || detected === "apt"\n'
        '          ? termuxLatest\n'
        '          : detected === "winget" ? wingetVersion() : release(detected).pipe(Effect.map((data) => data.version)),\n'
        '      ),\n'
        '    )\n',
    )
    replace_once(
        updater,
        '    const version = input.trim().replace(/^v/, "")\n    const packageName =\n',
        '    const version = input.trim().replace(/^v/, "")\n'
        '    if (method === "apt" && !nativeTermux) {\n'
        '      const prefix = process.env.PREFIX\n'
        '      if (!prefix || executable !== path.join(prefix, "bin", "opencode"))\n'
        '        return yield* Effect.fail(new Error("This binary is not installed by APT"))\n'
        '      const owner = yield* exec(["dpkg-query", "-S", executable]).pipe(Effect.orElseSucceed(() => undefined))\n'
        '      if (!owner || owner.code !== 0 || !owner.stdout.split("\\n").includes(`opencode: ${executable}`))\n'
        '        return yield* Effect.fail(new Error("This binary is not owned by the OpenCode APT package"))\n'
        '      yield* Effect.scoped(Effect.gen(function* () {\n'
        '        yield* flock.acquire("cli-upgrade", undefined, { timeoutMs: Duration.toMillis("5 hours") })\n'
        '        const updated = yield* exec(["apt-get", "update"], "30 minutes")\n'
        '        if (updated.code !== 0) return yield* Effect.fail(new Error(resultDetail(updated)))\n'
        '        const installed = yield* exec(["apt-get", "install", "--only-upgrade", "--yes", "opencode"], "4 hours")\n'
        '        if (installed.code !== 0) return yield* Effect.fail(new Error(resultDetail(installed)))\n'
        '        const actual = yield* exec([executable, "--version"])\n'
        '        const actualVersion = actual.stdout.trim().match(/(?:^|\\s)v?(\\d+\\.\\d+\\.\\d+)$/)?.[1]\n'
        '        if (actual.code !== 0 || actualVersion !== version)\n'
        '          return yield* Effect.fail(new Error(`APT did not install OpenCode ${version}: ${resultDetail(actual)}`))\n'
        '      }))\n'
        '      return\n'
        '    }\n'
        '    if (nativeTermux) {\n'
        '      const match = version.match(/^(\\d+\\.\\d+\\.\\d+)(?:-termux\\.([0-9]+))?$/)\n'
        '      if (!match) return yield* Effect.fail(new Error(`Unsupported native Termux release: ${input}`))\n'
        '      const expectedVersion = match[1]\n'
        '      const expectedRevision = match[2]\n'
        '      const expectedReleaseTag = expectedRevision === undefined ? "" : Number(expectedRevision) === 0 ? `v${expectedVersion}` : `v${expectedVersion}-${Number(expectedRevision)}`\n'
        '      yield* Effect.scoped(Effect.gen(function* () {\n'
        '        yield* flock.acquire("cli-upgrade", undefined, { timeoutMs: Duration.toMillis("5 hours") })\n'
        '        yield* fs.makeDirectory(global.cache, { recursive: true })\n'
        '        const directory = yield* temporaryDirectory("update-")\n'
        '        const installer = path.join(directory, "install.sh")\n'
        '        yield* runUpgrade({\n'
        '          method: "curl",\n'
        '          command: ["curl", "-fsSL", "--retry", "3", "-o", installer, `https://raw.githubusercontent.com/C04-wq/opencode-termux/main/install.sh`],\n'
        '          title: "Could not download the native Termux installer",\n'
        '        })\n'
        '        const result = yield* exec(["bash", "-c", \'OPENCODE_TERMUX_EXPECTED_VERSION="$1" OPENCODE_TERMUX_EXPECTED_RELEASE_TAG="$3" exec bash "$2"\', "opencode-termux-update", expectedVersion, installer, expectedReleaseTag], "4 hours")\n'
        '        if (result.code !== 0) return yield* Effect.fail(new Error(resultDetail(result)))\n'
        '        const actual = yield* exec([executable, "--version"])\n'
        '        const actualVersion = actual.stdout.trim().match(/(?:^|\\s)v?(\\d+\\.\\d+\\.\\d+)$/)?.[1]\n'
        '        if (actual.code !== 0 || actualVersion !== expectedVersion)\n'
        '          return yield* Effect.fail(new Error(`Native Termux installer did not install OpenCode ${expectedVersion}: ${resultDetail(actual)}`))\n'
        '      }))\n'
        '      return\n'
        '    }\n'
        '    const packageName =\n',
    )
    replace_once(
        updater,
        '    const commands: Record<Exclude<Method, "bun" | "curl" | "brew" | "winget">, string[]> = {\n',
        '    const commands: Record<Exclude<Method, "bun" | "curl" | "brew" | "winget" | "apt">, string[]> = {\n',
    )
    replace_once(
        updater,
        '        error\n'
        '          ? managedMessage(error)\n'
        '          : "Could not detect the installation method. Update with your package manager or download the latest release.",\n',
        '        error\n'
        '          ? managedMessage(error)\n'
        '          : "Could not detect the installation method. See https://github.com/C04-wq/opencode-termux#install for manual installation.",\n',
    )
    replace_once(
        updater,
        '        message:\n'
        '          "Could not detect the installation method. Update with your package manager or download the latest release.",\n',
        '        message:\n'
        '          "Could not detect the installation method. See https://github.com/C04-wq/opencode-termux#install for manual installation.",\n',
    )

    upgrade = root / "packages/cli/src/commands/handlers/upgrade.ts"
    replace_once(
        upgrade,
        '          new Error("Could not detect the installation method. Pass --method to choose how to upgrade OpenCode."),\n',
        '          new Error("Could not detect the installation method. See https://github.com/C04-wq/opencode-termux#install for manual installation."),\n',
    )

    # The released 2.2.7 bundle runs under `bun`, so process.execPath is the
    # interpreter, not the launcher. Method detection -- and uninstall, which
    # would otherwise delete the bun binary -- must use the wrapper the
    # launcher exports.
    replace_once(
        updater,
        "  const executable = yield* fs.realPath(process.execPath).pipe(Effect.orElseSucceed(() => process.execPath))\n",
        "  const launcher = process.env.OPENCODE_LAUNCHER\n"
        "  const executable = yield* fs\n"
        "    .realPath(launcher ?? process.execPath)\n"
        "    .pipe(Effect.orElseSucceed(() => launcher ?? process.execPath))\n",
    )

    upgrade_handler = root / "packages/cli/src/commands/handlers/upgrade.ts"
    replace_once(upgrade_handler, 'import { OPENCODE_VERSION } from "../../version"\n', "")
    replace_once(
        upgrade_handler,
        '      const method = Option.getOrUndefined(input.method) ?? (yield* updater.method())\n',
        '      const current = yield* updater.current()\n'
        '      const method = current.includes("-termux.") ? "curl" : Option.getOrUndefined(input.method) ?? (yield* updater.method())\n',
    )
    replace_once(upgrade_handler, '      if (version === OPENCODE_VERSION) {\n', '      if (version === current) {\n')
    replace_once(upgrade_handler, '      log.info(`From ${OPENCODE_VERSION} → ${version}`)\n', '      log.info(`From ${current} → ${version}`)\n')

    uninstall = root / "packages/cli/src/commands/handlers/uninstall.ts"
    text = uninstall.read_text(encoding="utf-8")
    if "const launcherPath" not in text:
        anchor = 'import { errorMessage } from "../../util/error"\n'
        if anchor not in text:
            raise SystemExit("patch-opencode-source: uninstall.ts imports changed upstream")
        # Replace first, then add the helper: its own body must keep the raw
        # process.execPath reference.
        text = text.replace("process.execPath", "launcherPath()")
        text = text.replace(
            anchor,
            anchor
            + "\nconst launcherPath = () => process.env.OPENCODE_LAUNCHER ?? process.execPath\n"
            + 'const isCurlMethod = (method: unknown): boolean => method === "curl"\n',
            1,
        )
        uninstall.write_text(text, encoding="utf-8")
    replace_once(
        uninstall,
        '    const shell = method === "curl" ? yield* shellConfigs(global.home) : []\n',
        '    const shell = isCurlMethod(method) ? yield* shellConfigs(global.home) : []\n',
    )
    replace_once(
        uninstall,
        '    const method = yield* updater.method()\n',
        '    const method = yield* updater.method()\n'
        '    // A bundle install owns a launcher script, not the interpreter bun.\n'
        '    const nativeBinary =\n'
        '      launcherPath() === path.join(global.home, ".local", "bin", "opencode") || isCurlMethod(method)\n',
    )
    replace_once(
        uninstall,
        '    if (method === "curl") log.info(`  Binary (manual removal): ${launcherPath()}`)\n'
        '    if (!method) log.warn("Could not detect the installation method. Remove the installation manually after cleanup.")\n',
        '    if (nativeBinary) log.info(`  Binary: ${launcherPath()}`)\n'
        '    else if (isCurlMethod(method)) log.info(`  Binary (manual removal): ${launcherPath()}`)\n'
        '    if (!method && !nativeBinary) log.warn("Could not detect the installation method. Remove the installation manually after cleanup.")\n',
    )
    replace_once(
        uninstall,
        '    if (method === "curl") {\n      log.message("To finish removing the binary, run:")\n',
        '    if (nativeBinary) {\n'
        '      yield* fs.remove(launcherPath()).pipe(\n'
        '        Effect.catch((error) => Effect.sync(() => errors.push(`Binary: ${errorMessage(error)}`))),\n'
        '      )\n'
        '      // The launcher script is not the installation: the module graph and\n'
        '      // native libraries live in the sibling lib/opencode directory.\n'
        '      const termuxRoot = process.env.PREFIX && launcherPath() === path.join(process.env.PREFIX, "bin", "opencode")\n'
        '        ? path.join(process.env.PREFIX, "lib", "opencode-termux")\n'
        '        : undefined\n'
        '      const root = termuxRoot && (yield* fs.exists(path.join(termuxRoot, ".opencode-termux-version")))\n'
        '        ? termuxRoot\n'
        '        : process.env.OPENCODE_ROOT\n'
        '      if (root) {\n'
        '        yield* fs.remove(root, { recursive: true, force: true }).pipe(\n'
        '          Effect.catch((error) => Effect.sync(() => errors.push(`Bundle: ${errorMessage(error)}`))),\n'
        '        )\n'
        '      }\n'
        '    }\n'
        '    if (!nativeBinary && isCurlMethod(method)) {\n      log.message("To finish removing the binary, run:")\n',
    )


if __name__ == "__main__":
    main()
