# TUR packaging prototype for OpenCode

This directory contains a first-pass package recipe intended for review in the
[Termux User Repository (TUR)](https://github.com/termux-user-repository/tur).
It is **not yet a merged TUR package** and has not been built in the TUR package
builder or tested on a clean Termux device.

## Current scope

- ARM64/aarch64 only; the recipe excludes `arm`, `i686`, and `x86_64` so TUR's architecture matrix does not try to package unsupported binaries.
- Uses the existing `v1.19.5` release archive from this project, pinned by SHA-256.
- Installs the runtime under `$PREFIX/lib/opencode-termux` and provides
  `$PREFIX/bin/opencode`.
- Lets `pkg`/APT own package upgrades; the launcher does not invoke npm or
  download a runtime during launch.
- Does not remove or rewrite the user's OpenCode configuration in `$HOME`.

The pinned archive is approximately 80 MB compressed. Confirm the installed
package size and TUR's current packaging requirements before submission.

## Build and validation still required

Run from a configured TUR build environment:

```bash
TERMUX_INSTALL_DEPS=true ./build-package.sh -a aarch64 opencode-termux
```

Then install the resulting package on a clean ARM64 Termux installation and
verify at least:

```bash
opencode --version
opencode --help
pkg upgrade
pkg uninstall opencode-termux
```

Before a TUR pull request is opened:

1. Confirm the release archive still exists and its digest matches the pinned
   `TERMUX_PKG_SHA256`.
2. Build the package in TUR's supported builder and inspect the resulting
   package contents and installed size. Add `opencode-termux` to TUR's
   `big-pkgs.list` if maintainers agree the archive warrants the low-disk-space
   preparation step in its CI workflow.
3. Test first launch, network/DNS access, TLS certificates, and normal OpenCode
   operation on a physical ARM64 Termux device.
4. Check the package metadata and recipe against the current TUR contribution
   guidelines.
5. Add automatic update metadata only after a reliable update strategy for the
   upstream runtime archive and checksum has been tested.

## Official Termux repository

There is already an open upstream package request:
[termux/termux-packages#25387](https://github.com/termux/termux-packages/issues/25387).
The request is not an acceptance decision. The project is also distributed via
npm, which may be a concern under the official repository's package policy.
TUR is the initial target for this prototype; official inclusion should be
discussed with Termux maintainers separately.
