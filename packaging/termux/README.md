# Termux official package: feasibility and implementation plan

**Status: prototype / not ready for submission.** This directory documents the packaging work separately from the existing curl installer. It does not claim that `pkg install opencode` is available.

## Goal

Submit a source-built `opencode` package to `termux/termux-packages`, so users can install and update it with Termux's package manager. The target is limited to the 64-bit architectures published by OpenCode: `aarch64` (ARM64) and `x86_64` (x64). 32-bit `arm` and `i686` are explicitly out of scope. The curl installer and GitHub Releases are the active distribution path. The former standalone `opencode-termux` manager/updater commands have been removed; update discovery is intended to remain inside OpenCode's built-in updater. This package proposal must not reintroduce a parallel manager or updater.

Architecture support is a release gate, not a marketing promise: an architecture is supported only after its runtime, every native addon, package build, installation, and real launch have passed. Unsupported architectures must fail early with a precise explanation rather than receive another architecture's binary.

The official package recipe ultimately belongs at `packages/opencode/build.sh` in `termux/termux-packages`. A recipe in this repository is only a development aid; it does not publish anything to Termux repositories.

## Verified integration points

- OpenCode source is pinned in `tools/supply-chain-lock.json`; the existing CI fetches the exact upstream commit from `https://github.com/anomalyco/opencode.git`.
- The existing pipeline builds the JavaScript bundle from source with a hash-verified host Bun, and builds Android/Bionic native components rather than shipping the upstream glibc/musl executable.
- Runtime dependencies already available as Termux packages are `bun`, `ripgrep` and `libc++`. The package recipe should declare runtime dependencies instead of downloading or installing them itself.
- OpenCode's official release targets include ARM64 (`aarch64`) and x64 (`x86_64` on Termux). This project deliberately follows that upstream architecture list rather than attempting unsupported 32-bit ports.
- `packing/launcher/opencode` is already relocatable relative to its own location and uses Termux's Bun.
- The current source pipeline is not yet a Termux package build: it assumes a Linux x86_64 GitHub Actions host, a separately provisioned Android NDK, Zig, Rust targets, and generated artifacts under `artifacts/transplant`.

## Submission blockers

### 1. Package size

The currently published ARM64 runtime archive in release `v2.3.2-2` is 39,580,614 bytes (about 37.8 MiB compressed). This is a warning sign, not proof that the final `.deb` exceeds the limit: Termux's policy applies to the resulting package, whose compression and metadata differ from this tarball.

The final `.deb` must be built and measured before declaring the size requirement passed or failed. If it exceeds 100 MiB, reduce the package or request an explicit exception from maintainers. Do not hide files from the package merely to pass the size check if they are required at runtime.

### 2. Architecture support

The current shipped runtime is ARM64-only. The intended Termux target matrix is:

| Termux architecture | OpenCode upstream target | Current status |
| --- | --- | --- |
| `aarch64` | ARM64 | Existing project target; needs continued validation |
| `x86_64` | x64 | PTY shared library cross-build passes CI; full runtime remains unsupported |

Although Termux itself supports 32-bit architectures, those targets are not in OpenCode's official release matrix. This project will not build or advertise `arm` or `i686`; they are explicitly excluded.

The project now publishes ARM64 and x86_64 runtime assets. The x86_64 path uses an Android/Bionic OpenTUI build, a source-built Parcel watcher, architecture-specific PTY and bundle paths, and a source-built FFF C ABI. GitHub Actions builds and validates the two architectures independently. The published x86_64 asset is not, by itself, proof of successful operation on every x86_64 Termux device; real-device launch and interactive TUI checks remain valuable acceptance evidence.

### 3. Termux build-system integration

The existing GitHub Actions pipeline must be made reproducible through Termux's package build environment. The eventual `build.sh` must:
- fetch only official source archives or pinned Git commits and verify immutable source references;
- use Termux build-system variables and dependencies rather than hard-coded host paths;
- compile native libraries for the selected Android target with the supported NDK/toolchain;
- install only into the package staging prefix;
- avoid root, network access during package installation, and writes outside the build directory or staging prefix;
- package notices and licenses for all bundled dependencies;
- pass the package build and lint checks for every supported architecture.

### 4. Native dependency portability

The production release metadata, GitHub Release assets, curl installer, launcher, archive validator, smoke test and device test support both `aarch64` and `x86_64`. Each architecture has a distinct checksum and archive name. The separate Termux package recipe remains unfinished and must not be confused with the already-published curl-based runtime distribution.

## Implementation sequence

1. Keep `aarch64` as the known project target and establish a complete baseline test suite.
2. Make the build pipeline architecture-parameterized rather than copying the AArch64 workflow: toolchain triples, NDK sysroots, Rust targets, OpenTUI target, native addon selection, archive names, checksums and release metadata must all derive from one validated architecture definition.
3. Add `x86_64` end-to-end first: Bun runtime availability, OpenTUI, PTY, watcher, FFF, bundle, launcher, installer detection, release assets and CI/device tests.
4. Keep `arm` and `i686` outside the project target matrix and reject them clearly rather than publishing binaries for unsupported targets.
5. Reduce the installed and compressed package size; identify the largest files and determine which are essential.
6. Implement a real Termux `packages/opencode/build.sh` recipe using source builds and declared dependencies.
7. Add CI that runs the official `termux-packages` build tooling and validates the resulting `.deb` metadata, contents, ELF architecture, dependencies, size and license notices.
8. Test installation, upgrade, downgrade/rollback where supported, removal and a real OpenCode launch in Termux on every claimed architecture.
9. Only after those gates pass, prepare a separate pull request to `termux/termux-packages`. A pull request is not an acceptance guarantee; maintainers decide policy exceptions and repository inclusion.

## Acceptance gates

- [ ] Final `.deb` is below 100 MiB, or Termux maintainers explicitly approve an exception.
- [ ] Architecture support is explicit and accepted by maintainers.
- [ ] Only the two official OpenCode 64-bit targets are in scope: Termux `aarch64` (ARM64) and `x86_64` (x64).
- [ ] Both advertised architectures have a compatible Android/Bionic JavaScript runtime and all native modules; no 32-bit architecture is advertised.
- [ ] Build is reproducible from pinned source in the Termux package build system.
- [ ] No prebuilt upstream ELF, glibc binary, npm install, or curl-based installer is used by the package install process.
- [ ] Runtime dependencies are declared in package metadata.
- [ ] Package staging contains no files outside the intended package.
- [ ] Package build, lint, ELF, dependency, license and size checks pass.
- [ ] Real-device installation and runtime smoke tests pass on every advertised architecture.
- [ ] Existing curl installation path remains unchanged and independently tested.

## Upstream policy references

- [Termux packaging policy and contribution checklist](https://github.com/termux/termux-packages/blob/master/CONTRIBUTING.md)
- [Creating a new Termux package](https://github.com/termux/termux-packages/wiki/Creating-new-package)
- [Termux package build instructions](https://github.com/termux/termux-packages/wiki/Building-packages)
- [Official Termux Bun build recipe](https://github.com/termux/termux-packages/blob/master/packages/bun/build.sh)
