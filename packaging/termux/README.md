# Termux official package: feasibility and implementation plan

**Status: prototype / not ready for submission.** This directory documents the packaging work separately from the existing curl installer. It does not claim that `pkg install opencode` is available.

## Goal

Submit a source-built `opencode` package to `termux/termux-packages`, so users can install and update it with Termux's package manager. The target is limited to the 64-bit architectures published by OpenCode: `aarch64` (ARM64) and `x86_64` (x64). 32-bit `arm` and `i686` are explicitly out of scope. The current installer, manager, updater and GitHub Releases remain independent and must not be removed or changed as part of this effort.

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

The latest published ARM64 runtime archive is 122,380,887 bytes (about 116.7 MiB compressed). This is a warning sign, not proof that the final `.deb` exceeds the limit: Termux's policy applies to the resulting package, whose compression and metadata differ from this tarball.

The final `.deb` must be built and measured before declaring the size requirement passed or failed. If it exceeds 100 MiB, reduce the package or request an explicit exception from maintainers. Do not hide files from the package merely to pass the size check if they are required at runtime.

### 2. Architecture support

The current shipped runtime is ARM64-only. The intended Termux target matrix is:

| Termux architecture | Android target | Current status |
| --- | --- | --- |
| `aarch64` | `aarch64-linux-android` | Existing project target; needs continued validation |
| `x86_64` | `x86_64-linux-android` | PTY shared library cross-build passes CI; full runtime remains unsupported |
| `arm` | `armv7a-linux-androideabi` | Blocked by Termux's Bun package excluding 32-bit ARM |
| `i686` | `i686-linux-android` | Blocked by Termux's Bun package excluding 32-bit x86 |

Although Termux itself supports 32-bit architectures, upstream OpenCode does not publish official 32-bit ARM or x86 targets. This project will not build or advertise `arm` or `i686`; those architectures are outside the supported target matrix.

The first practical expansion target is `x86_64`, while retaining `aarch64`. The official Termux Bun recipe supports x86_64, so the JavaScript runtime itself is available there. The remaining native chain is not ready: the current OpenCode lock contains only `@parcel/watcher-android-arm64` and `@ff-labs/fff-bin-android-arm64`; OpenTUI is built only for AArch64; and the bundle/installer are AArch64-specific. FFF is an optimization and may be disabled on x86_64 to retain the ripgrep fallback, but the watcher must be built from source for Android x86_64 (or replaced with a compatible implementation). The PTY build helper now has an x86_64 cross-build path, and CI has successfully produced and ELF-verified the x86_64 Bionic shared library. This validates only that one component, not the complete runtime. No x86_64 support claim is valid until all of these pieces are integrated and the resulting runtime is launched on a real x86_64 Termux device.

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

The current bundle pipeline is still AArch64-only. `scripts/ci/build-rust-pty-android.sh` now accepts an explicit `TARGET_ARCH` for Android NDK cross-builds of the PTY library (`aarch64` or `x86_64`) and validates the resulting ELF machine. This is an isolated native-dependency improvement, not end-to-end x86_64 support: `scripts/ci/build-opencode-bundle.sh`, the OpenTUI build workflow, FFF selection, watcher selection, archive naming/validation, release metadata and installer remain AArch64-specific. Those components need genuine per-architecture builds and tests; a matching CPU label alone is not sufficient.

## Implementation sequence

1. Keep `aarch64` as the known project target and establish a complete baseline test suite.
2. Make the build pipeline architecture-parameterized rather than copying the AArch64 workflow: toolchain triples, NDK sysroots, Rust targets, OpenTUI target, native addon selection, archive names, checksums and release metadata must all derive from one validated architecture definition.
3. Add `x86_64` end-to-end first: Bun runtime availability, OpenTUI, PTY, watcher, FFF, bundle, launcher, installer detection, release assets and CI/device tests.
4. Investigate a maintainable Android/Bionic JavaScript runtime for `arm` and `i686`. Evaluate upstream Bun support and viable alternatives; do not assume Node.js is a drop-in replacement because OpenCode currently relies on Bun APIs and package behavior. Until a complete runtime path exists, fail clearly rather than publishing broken packages.
5. Reduce the installed and compressed package size; identify the largest files and determine which are essential.
6. Implement a real Termux `packages/opencode/build.sh` recipe using source builds and declared dependencies.
7. Add CI that runs the official `termux-packages` build tooling and validates the resulting `.deb` metadata, contents, ELF architecture, dependencies, size and license notices.
8. Test installation, upgrade, downgrade/rollback where supported, removal and a real OpenCode launch in Termux on every claimed architecture.
9. Only after those gates pass, prepare a separate pull request to `termux/termux-packages`. A pull request is not an acceptance guarantee; maintainers decide policy exceptions and repository inclusion.

## Acceptance gates

- [ ] Final `.deb` is below 100 MiB, or Termux maintainers explicitly approve an exception.
- [ ] Architecture support is explicit and accepted by maintainers.
- [ ] The intended four-architecture Termux matrix has been evaluated; every advertised architecture has a compatible Android/Bionic JavaScript runtime and all native modules.
- [ ] `aarch64` and `x86_64` are validated first; `arm` and `i686` remain explicit blockers until their runtime and native dependency chains are proven.
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
