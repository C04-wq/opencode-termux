# Termux official package: feasibility and implementation plan

**Status: prototype / not ready for submission.** This directory documents the packaging work separately from the existing curl installer. It does not claim that `pkg install opencode` is available.

## Goal

Submit a source-built `opencode` package to `termux/termux-packages`, so users can install and update it with Termux's package manager. The current installer, manager, updater and GitHub Releases remain independent and must not be removed or changed as part of this effort.

The official package recipe ultimately belongs at `packages/opencode/build.sh` in `termux/termux-packages`. A recipe in this repository is only a development aid; it does not publish anything to Termux repositories.

## Verified integration points

- OpenCode source is pinned in `tools/supply-chain-lock.json`; the existing CI fetches the exact upstream commit from `https://github.com/anomalyco/opencode.git`.
- The existing pipeline builds the JavaScript bundle from source with a hash-verified host Bun, and builds Android/Bionic native components rather than shipping the upstream glibc/musl executable.
- Runtime dependencies already available as Termux packages are `bun`, `ripgrep` and `libc++`. The package recipe should declare runtime dependencies instead of downloading or installing them itself.
- `packing/launcher/opencode` is already relocatable relative to its own location and uses Termux's Bun.
- The current source pipeline is not yet a Termux package build: it assumes a Linux x86_64 GitHub Actions host, a separately provisioned Android NDK, Zig, Rust targets, and generated artifacts under `artifacts/transplant`.

## Submission blockers

### 1. Package size

The latest published ARM64 runtime archive is 122,380,887 bytes (about 116.7 MiB compressed). Termux's packaging policy says the resulting package should be below 100 MiB. This is a hard submission blocker until the package is reduced or Termux maintainers explicitly accept an exception.

The package-size gate must measure the final `.deb`, not just a source archive or an intermediate bundle. Do not hide files from the package merely to pass the size check if they are required at runtime.

### 2. Architecture support

The current runtime is ARM64-only. The build pipeline explicitly targets `aarch64-linux-android`; the PTY library, file watcher and FFF Android native dependency are ARM64-specific. The OpenTUI build is also hard-coded to AArch64.

Termux builds packages for `aarch64`, `arm`, `i686` and `x86_64`. Before proposing architecture exclusions, confirm with Termux maintainers whether an ARM64-only package is acceptable. Do not advertise support for other architectures or silently ship incompatible native assets.

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

The current scripts are not architecture-generic. In particular, `scripts/ci/build-rust-pty-android.sh`, `scripts/ci/build-opencode-bundle.sh`, and the OpenTUI build workflow assume AArch64. The FFF and watcher packages are selected as Android ARM64 dependencies. These need either genuine per-architecture builds or an explicit, maintainer-approved architecture restriction.

## Implementation sequence

1. Reduce the installed and compressed package size; identify the largest files and determine which are essential.
2. Generalize the native build scripts around Termux target architecture, NDK and staging-prefix variables.
3. Verify that each required native dependency exists and builds for each proposed architecture.
4. Implement a real Termux `packages/opencode/build.sh` recipe using source builds and declared dependencies.
5. Add CI that runs the official `termux-packages` build tooling and validates the resulting `.deb` metadata, contents, ELF architecture, dependencies, size and license notices.
6. Test installation, upgrade, downgrade/rollback where supported, removal and a real OpenCode launch in Termux.
7. Only after those gates pass, prepare a separate pull request to `termux/termux-packages`. A pull request is not an acceptance guarantee; maintainers decide policy exceptions and repository inclusion.

## Acceptance gates

- [ ] Final `.deb` is below 100 MiB, or Termux maintainers explicitly approve an exception.
- [ ] Architecture support is explicit and accepted by maintainers.
- [ ] Build is reproducible from pinned source in the Termux package build system.
- [ ] No prebuilt upstream ELF, glibc binary, npm install, or curl-based installer is used by the package install process.
- [ ] Runtime dependencies are declared in package metadata.
- [ ] Package staging contains no files outside the intended package.
- [ ] Package build, lint, ELF, dependency, license and size checks pass.
- [ ] Real-device installation and runtime smoke tests pass.
- [ ] Existing curl installation path remains unchanged and independently tested.

## Upstream policy references

- [Termux packaging policy and contribution checklist](https://github.com/termux/termux-packages/blob/master/CONTRIBUTING.md)
- [Creating a new Termux package](https://github.com/termux/termux-packages/wiki/Creating-new-package)
- [Termux package build instructions](https://github.com/termux/termux-packages/wiki/Building-packages)
