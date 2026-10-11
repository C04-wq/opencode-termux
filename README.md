<p align="center">
  <a href="https://opencode.ai">
    <img src="https://raw.githubusercontent.com/C04-wq/opencode-termux/main/opencode-logo.svg" alt="OpenCode" width="64" height="80">
  </a>
</p>

<h1 align="center">opencode-termux</h1>

<p align="center">
  <a href="https://www.npmjs.com/package/opencode-termux"><img src="https://img.shields.io/npm/v/opencode-termux?style=for-the-badge" alt="npm"></a>
  <img src="https://img.shields.io/badge/Platform-Termux-green?style=for-the-badge" alt="Termux">
  <img src="https://img.shields.io/badge/Architecture-aarch64-blue?style=for-the-badge" alt="aarch64">
  <a href="https://github.com/C04-wq/opencode-termux/actions/workflows/auto-update.yml"><img src="https://img.shields.io/github/actions/workflow/status/C04-wq/opencode-termux/auto-update.yml?style=for-the-badge&label=release" alt="Release workflow"></a>
</p>

<p align="center"><b>OpenCode on Android through Termux — automatic setup, verified runtime files, and no root required.</b></p>

**opencode-termux** is a compatibility and distribution layer for running the official OpenCode ARM64 musl build on Android's Termux environment. It provides a command named `opencode`, checks the local prerequisites, downloads and validates the matching runtime, adapts the binary to Termux's filesystem and DNS layout, and optionally updates the npm package automatically.

This project does not implement a separate AI coding agent. It packages and launches OpenCode, while handling the environment-specific work needed to make its Linux ARM64 musl executable run under Termux.

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [What happens when you run opencode](#what-happens-when-you-run-opencode)
- [Dependency checks](#dependency-checks)
- [Runtime installation and integrity](#runtime-installation-and-integrity)
- [Automatic package updates](#automatic-package-updates)
- [How the Android compatibility layer works](#how-the-android-compatibility-layer-works)
- [Automated build and release pipeline](#automated-build-and-release-pipeline)
- [Configuration, troubleshooting, and repair](#configuration-troubleshooting-and-repair)
- [Uninstall](#uninstall)
- [Repository layout](#repository-layout)
- [Limitations and security notes](#limitations-and-security-notes)

## Requirements

- Android device or environment running **Termux on ARM64/aarch64**.
- Node.js and npm in Termux. Install them with:

  ```bash
  pkg update
  pkg install nodejs
  ```

- Internet access for initial setup, downloading the runtime, and checking npm for updates.
- Enough free storage for the downloaded archive, temporary extraction, and installed runtime.

Root access, Proot, Docker, and an Alpine installation inside Termux are **not** required. Alpine is used by the hosted build workflow to obtain and verify runtime libraries; it is not installed on the user's phone.

This package is specifically designed for Termux's standard prefix at `/data/data/com.termux/files/usr`. It is not a generic Linux installer and does not target x86_64 or 32-bit ARM devices.

## Install

Run these commands in Termux:

```bash
pkg install nodejs
npm install -g opencode-termux
opencode
```

The npm package installs the launcher and installer scripts. The larger OpenCode runtime is downloaded on first launch into `~/.opencode/`, rather than being bundled as a large binary payload inside the npm package.

To pass arguments to OpenCode, append them as you normally would:

```bash
opencode --version
opencode .
```

The wrapper forwards the supplied arguments to the OpenCode executable.

## What happens when you run `opencode`

The launcher in `bin/opencode` coordinates setup, runtime validation, update checks, and the final process launch. It is designed to make normal launches quiet while stopping with a clear error if a required setup step fails.

```text
User runs: opencode [arguments]
        |
        v
1. Check Termux dependencies
        |
        +-- All present --> continue silently
        |
        +-- Missing -----> install missing packages with pkg
                            show a short English status message
        |
        v
2. Check local OpenCode runtime
        |
        +-- Complete and version matches --> reuse it
        |
        +-- Missing, incomplete, or stale --> download and validate runtime
        |
        v
3. Check npm for a newer published package
   (no more than once per 24 hours by default)
        |
        +-- No newer version / check unavailable --> keep current package
        |
        +-- New version found --> install package and restart the launcher
                                  so the new package can prepare its runtime
        |
        v
4. Set runtime library and TLS environment
        |
        v
5. Execute OpenCode with the original arguments
```

### First launch

On the first launch, the runtime normally does not exist yet. The installer downloads the archive corresponding to the installed npm package, verifies its SHA-256 digest, extracts it into a temporary directory, checks that the required files are present, adjusts the executable's interpreter, and runs a version test. Only after these checks does it activate the runtime under `~/.opencode/`.

### Subsequent launches

When all Termux dependencies are already available and the runtime files and version marker match the installed package, the dependency check is silent and the runtime is reused. The launcher still performs its configured npm version-check logic, but the network check is rate-limited by default.

If a required runtime file is missing or the runtime marker does not match the installed npm package, the installer prepares the matching runtime again. A setup error stops the launch rather than intentionally continuing with an incomplete runtime.

## Dependency checks

Every invocation of `opencode` runs the dependency check. If everything is available, it returns without printing a setup message. If something is missing, the installer displays:

```text
◇ Installing required dependencies…
✓ Termux dependencies are ready
```

The actual package-manager output is kept quiet on successful setup. If installation fails, an error is printed and the launcher exits.

The installer checks for these commands and files:

| Requirement | Termux package or source | Purpose |
| --- | --- | --- |
| `curl` | `curl` | Downloads the runtime archive over HTTPS. |
| `tar` | `tar` | Extracts the downloaded archive. |
| `patchelf` | `patchelf` | Sets the executable's ELF interpreter for the packaged runtime. |
| `timeout` | `coreutils` | Bounds the npm version-check request. |
| TLS certificate bundle | `ca-certificates` | Supplies certificates for HTTPS/TLS verification. |
| Termux resolver configuration | `resolv-conf` | Provides the DNS configuration used by the packaged musl runtime. |

Missing items are installed through Termux's `pkg install -y` command. This requires a working Termux package configuration and network connection when a package needs to be installed. The script checks again after installation; if a requirement is still missing, it reports an error.

## Runtime installation and integrity

### Where files are stored

- **Launcher and JavaScript installer:** installed by npm, normally under Termux's global npm prefix.
- **Managed OpenCode runtime:** `~/.opencode/`.
- **Runtime version marker:** `~/.opencode/.opencode-termux-version`.
- **Update-check cache:** `$XDG_CACHE_HOME/opencode-termux/last-update-check`, or `~/.cache/opencode-termux/last-update-check` when `XDG_CACHE_HOME` is not set.
- **OpenCode configuration:** normally `~/.config/opencode/`; this project does not use `~/.opencode/` as the configuration directory.

The managed runtime contains the OpenCode executable, the musl loader and compatibility library, and the required C++ support libraries. The marker records which npm package version prepared that runtime. The marker is used to detect when the npm package and local runtime are out of sync.

### Verification and activation

The npm package includes `release-checksums.json`, which records the expected SHA-256 digest and package version for its runtime archive. Before extraction or activation, the installer checks that the checksum metadata matches the package version and that the downloaded archive's digest matches the expected digest.

The installer then:

1. Downloads only from the project's HTTPS GitHub Release URL, with retries.
2. Verifies the archive's SHA-256 digest.
3. Extracts into a temporary directory and checks for all required runtime files.
4. Adjusts the executable's interpreter and tests that it can print its version.
5. Stages a complete runtime beside the destination directory.
6. Activates the staged directory using renames and tests the runtime again at its final path.
7. Restores the previous runtime if activation or the final-path test fails.

This reduces the chance of leaving a half-written runtime in the active directory. It does not mean that every possible runtime failure can be prevented, nor does a checksum by itself prove that upstream source code is safe. The checksum protects against an archive that does not match the digest shipped in the npm package.

## Automatic package updates

By default, the launcher checks npm for a newer published `opencode-termux` version **at most once every 24 hours**. The request uses `npm view opencode-termux version` with a 10-second timeout. It checks the published package version; it does not upload prompts, project files, or source code as part of that version query.

- If the check finds no newer version, OpenCode starts using the installed runtime.
- If the check cannot complete, the launcher continues with the installed version.
- If a newer version is found, the launcher attempts to install that exact version of the npm package and restarts through the updated launcher. The new launcher can then install the runtime that matches its own package version.
- If the npm update fails, the launcher warns and attempts to use the already installed version.

The OpenCode executable's own updater is disabled by the wrapper. This prevents OpenCode from replacing the compatibility-adjusted binary with an unmodified upstream build that may not work correctly in Termux.

Control the check with an environment variable:

```bash
# Disable the automatic npm version check for this launch
OPENCODE_TERMUX_AUTOUPDATE=0 opencode

# Explicitly enable it (the default)
OPENCODE_TERMUX_AUTOUPDATE=1 opencode

# Inspect the latest version published to npm
npm view opencode-termux version

# Install the latest published package immediately
npm install -g opencode-termux@latest
```

The automatic check is not the same as the build pipeline: a source change on GitHub becomes available to users only after a package version has been successfully published to npm.

## How the Android compatibility layer works

OpenCode's official Linux ARM64 musl archive is the starting point, but Android and Termux differ from a conventional Linux distribution in important ways.

### Musl loader and libraries

The build includes a musl dynamic loader and the runtime libraries needed by the official executable. The launcher starts OpenCode through the packaged loader and explicitly sets the library search path to `~/.opencode/`. It also removes `LD_PRELOAD` for the launch to avoid an inherited preload library interfering with the packaged runtime.

### DNS on Android

Android does not provide the conventional `/etc/resolv.conf` path expected by a stock musl resolver. Without a suitable resolver configuration, DNS lookups can fail even when the device has network connectivity.

To address this, the build compiles a pinned musl version with its resolver configuration path changed to Termux's `/data/data/com.termux/files/usr/etc/resolv.conf`. The dependency check ensures the Termux resolver file is present, and the launcher uses the packaged musl loader so this runtime is the one used by OpenCode.

### TLS certificates

The launcher sets `SSL_CERT_FILE` to Termux's certificate bundle at `/data/data/com.termux/files/usr/etc/tls/cert.pem`. This allows TLS-aware components in the packaged runtime to find the expected certificate file. The `ca-certificates` package is installed if the file is missing.

### C++ support libraries

The archive includes `libgcc_s.so.1` and `libstdc++.so.6`, obtained from Alpine's ARM64 packages during the hosted build. The build verifies that the expected files exist and that the OpenCode executable declares the relevant library dependencies. The C++ library is normalized to a stable runtime filename so the launcher can find it consistently.

These measures target the compatibility issues handled by this project; they do not turn Android into a full desktop Linux distribution. OpenCode features that depend on other system capabilities may still have platform-specific limitations.

## Automated build and release pipeline

The GitHub Actions workflow [Build and publish Termux package](.github/workflows/auto-update.yml) runs on a six-hour schedule, can be started manually, and runs when relevant source or build-tooling files are pushed to `main`. It creates a package revision so changes to this wrapper or its build process can reach users even if upstream OpenCode has not released a new version.

At a high level, the pipeline:

1. Queries the official OpenCode GitHub release API for the latest version and the SHA-256 digest of its ARM64 musl archive.
2. Resolves a package version and checks whether the corresponding npm package and GitHub Release already exist. If only one side exists, it stops rather than risking inconsistent release metadata.
3. Sets up an isolated Alpine root on the hosted runner and installs ARM64 `libgcc` and `libstdc++` using Alpine's `apk` package manager and trusted signing keys. No container daemon is required.
4. Downloads the official OpenCode archive over HTTPS and verifies its digest against the digest published by upstream.
5. Builds the pinned musl runtime with the Termux DNS resolver path, assembles the ARM64 archive, and calculates the archive SHA-256.
6. Runs syntax checks, inspects the archive contents, and performs an npm packaging dry run.
7. Publishes the npm package, creates a matching GitHub Release, and commits the generated package-version and checksum metadata.

Publishing jobs are serialized to prevent concurrent runs from publishing conflicting versions. The workflow fails closed when required upstream checksum data is missing or the npm/GitHub Release state disagrees. A successful GitHub commit alone is not proof that publication succeeded: check the [Actions workflow](https://github.com/C04-wq/opencode-termux/actions/workflows/auto-update.yml) and [npm package page](https://www.npmjs.com/package/opencode-termux) to confirm the release.

### Toolchain maintenance

The separate [toolchain update workflow](.github/workflows/toolchain-updates.yml) checks Alpine's official stable-release information and validates a candidate build before updating the pinned Alpine branch. The musl source version is intentionally pinned separately; the build checks its SHA-256, so an unreviewed or mismatched source archive fails rather than being silently accepted.

## Configuration, troubleshooting, and repair

### Check versions

```bash
# Installed npm package version
npm list -g opencode-termux --depth=0

# Latest version published to npm
npm view opencode-termux version

# OpenCode runtime version
opencode --version
```

### Update immediately

```bash
npm install -g opencode-termux@latest
opencode
```

### Re-prepare the managed runtime

If the runtime is missing, incomplete, or its version marker is out of date, running `opencode` normally triggers the installer. To explicitly make the installer re-check the runtime, remove only the marker and launch again:

```bash
rm -f ~/.opencode/.opencode-termux-version
opencode
```

The installer will prepare and validate the runtime that matches the currently installed npm package. This does not uninstall the npm package or intentionally remove OpenCode's configuration.

### Common problems

- **Unsupported architecture:** the package supports ARM64/aarch64 only. Check with `node -p 'process.arch'`; the expected result is `arm64`.
- **Dependency installation fails:** make sure Termux's `pkg` repositories are configured and reachable. The launcher stops if a required dependency cannot be installed.
- **Download or checksum error:** check connectivity and retry later. Do not bypass checksum verification; the checksum metadata must match the package's runtime archive.
- **DNS or TLS errors:** verify that Termux's `resolv-conf` and `ca-certificates` packages are installed and that their expected files exist.
- **Automatic update does not happen immediately:** the check is rate-limited to once per 24 hours. Install the package manually with `npm install -g opencode-termux@latest` to update immediately.
- **GitHub has newer source changes but npm does not:** the source changes are not yet available through the normal package installation until the release workflow publishes them.

If a problem persists, open an issue with the error message and relevant version information. Avoid including API keys, tokens, private prompts, or other secrets in a bug report.

## Uninstall

```bash
npm uninstall -g opencode-termux
rm -rf ~/.opencode
```

The first command removes the npm-installed launcher and scripts. The second removes the runtime directory managed by this package. It does not remove `~/.config/opencode/`, which normally contains OpenCode configuration; remove that directory separately only if you intentionally want to delete that configuration too.

## Repository layout

| Path | Responsibility |
| --- | --- |
| `bin/opencode` | Entry point: checks dependencies, validates the runtime version, checks for package updates, sets the runtime environment, and launches OpenCode. |
| `install.js` | Installs missing Termux prerequisites and downloads, verifies, tests, and activates the matching runtime. |
| `package.json` | npm package metadata, version, and the command entry point. |
| `release-checksums.json` | Expected SHA-256 and version for the runtime archive associated with the package. |
| `scripts/build-android-release.sh` | Builds the Termux-compatible ARM64 archive from the official OpenCode binary and runtime libraries. |
| `.github/workflows/auto-update.yml` | Detects upstream releases, builds the archive, and publishes npm/GitHub releases. |
| `.github/workflows/toolchain-updates.yml` | Validates and maintains the pinned Alpine build toolchain. |
| `scripts/check-toolchain-updates.mjs` | Checks Alpine stable-branch information for toolchain maintenance. |

## Limitations and security notes

- This project targets Termux on ARM64/aarch64, not every Android architecture or Linux distribution.
- The first setup and future updates need network access; already-installed runtime files can be reused when offline, but dependency installation and version checks may need the network.
- The project does not bypass OpenCode authentication, API-provider requirements, or service terms. Configure providers and credentials through OpenCode's normal supported mechanisms.
- Checksums validate that the downloaded archive matches the digest packaged with the npm release. They are an integrity check, not a guarantee that upstream software is vulnerability-free.
- The automatic npm version check sends a request to the npm registry for the package version. It does not send your coding session or project files as part of that check. OpenCode itself may make network requests to the AI providers and services you configure.
- Runtime files under `~/.opencode/` are managed by this package. Avoid manually replacing individual files there, as doing so can break the version and integrity assumptions.

## License

[MIT](LICENSE)
