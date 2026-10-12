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

**opencode-termux** is a compatibility and distribution layer for running the official OpenCode Linux ARM64/musl build in Termux. It installs a command named `opencode`, checks the Termux prerequisites, downloads and verifies a matching runtime archive, adapts the executable to Termux's filesystem and DNS layout, and can update its own npm package.

This repository does **not** implement a separate AI coding agent or provide AI models/API access. It packages and launches OpenCode and handles platform-specific runtime compatibility.


## Screenshots

<p align="center">
  <img src="https://raw.githubusercontent.com/C04-wq/opencode-termux/main/screenshots/screenshot-1.png" alt="OpenCode running in Termux" width="49%">
  <img src="https://raw.githubusercontent.com/C04-wq/opencode-termux/main/screenshots/screenshot-2.png" alt="OpenCode session in Termux" width="49%">
  <img src="https://raw.githubusercontent.com/C04-wq/opencode-termux/main/screenshots/screenshot-3.png" alt="OpenCode coding workflow in Termux" width="49%">
  <img src="https://raw.githubusercontent.com/C04-wq/opencode-termux/main/screenshots/screenshot-4.png" alt="OpenCode interface in Termux" width="49%">
</p>

## Contents

- [Requirements and scope](#requirements-and-scope)
- [Installation and first launch](#installation-and-first-launch)
- [Launch lifecycle](#launch-lifecycle)
- [Dependencies checked at launch](#dependencies-checked-at-launch)
- [Runtime files, verification, and recovery](#runtime-files-verification-and-recovery)
- [API keys and provider credentials](#api-keys-and-provider-credentials)
- [Automatic package updates](#automatic-package-updates)
- [Why the compatibility layer is needed](#why-the-compatibility-layer-is-needed)
- [Build and release automation](#build-and-release-automation)
- [Troubleshooting](#troubleshooting)
- [Uninstalling](#uninstalling)
- [Repository map](#repository-map)
- [Limitations and security notes](#limitations-and-security-notes)
- [License](#license)

## Requirements and scope

- An Android device running **Termux on ARM64/aarch64**.
- Node.js and npm available inside Termux.
- Internet access for initial runtime download, dependency installation when required, and npm version checks.
- Enough free storage for the compressed archive, temporary extraction, and runtime files.

Install Node.js from Termux's package repositories if needed:

```bash
pkg update
pkg install nodejs
```

Check the Node.js architecture with:

```bash
node -p 'process.arch'
```

The expected output is `arm64`. The installer exits with an error on other Node architectures. The package is designed for Termux's standard prefix, `/data/data/com.termux/files/usr`; it is not a general-purpose Linux installer.

**Root, Proot, Docker, and Alpine installed on the phone are not required.** Alpine is used by the hosted build process to obtain signed ARM64 support libraries. The phone receives the resulting runtime archive.

## Installation and first launch

Run in Termux:

```bash
npm install -g opencode-termux
opencode
```

The npm package installs the launcher and JavaScript installer. It does not bundle the large OpenCode executable/runtime inside the npm package. On first launch, the installer downloads the runtime archive associated with the installed package version and prepares it under `~/.opencode/`.

Useful commands:

```bash
opencode --version
opencode .
```

The launcher passes arguments through to OpenCode. Run `opencode --help` to see the options supported by the installed OpenCode version.

## Launch lifecycle

The main entry point is `bin/opencode`; runtime setup and verification are implemented in `install.js`. Each time you run `opencode`, the process is approximately:

```text
opencode [arguments]
    |
    v
1. Run install.js --ensure-dependencies
    |-- Required tools/files already present -> no setup message
    |-- Something missing -> try pkg install -y for the missing items
    |                            |
    |                            +-- failure -> stop and report an error
    v
2. Check the managed runtime in ~/.opencode/
    |-- Required files and version marker match -> reuse runtime
    |-- Missing/incomplete/out of date -> download and prepare runtime
    |                            |
    |                            +-- checksum/test/setup failure -> stop
    v
3. Optionally query npm for the latest published package version
    |-- No newer version / check unavailable -> use installed version
    |-- New version found -> install that package and re-enter the launcher
    v
4. Set runtime library and certificate environment
    v
5. Execute the packaged OpenCode binary with the original arguments
```

### Quiet normal launches

The dependency check is intentionally silent if every required command and file is already available. It does not reinstall those packages on every launch. If a dependency is missing, the installer prints `Installing required dependencies…`, asks Termux's `pkg` to install the missing package(s), then checks again.

The dependency-only mode (`--ensure-dependencies`) exits after checking prerequisites; it does not itself download the OpenCode runtime. The launcher separately checks whether the runtime is ready.

### First launch and later launches

On a first launch, or when the runtime is missing or out of sync with the installed npm package, `install.js`:

1. Checks that the process is ARM64 and that `HOME` is set.
2. Confirms that `release-checksums.json` describes the same package version as `package.json`, with a valid SHA-256 value.
3. Downloads the release archive from this project's GitHub Releases over HTTPS, with retries.
4. Calculates SHA-256 and compares it with the digest included in the npm package.
5. Extracts into a temporary directory and verifies the required runtime files.
6. Uses `patchelf` to set the executable's interpreter to the packaged musl loader.
7. Runs the executable's `--version` test before activation.
8. Copies the prepared files into a staging directory beside `~/.opencode/`, activates that directory with renames, and tests the executable again from its final path.
9. Restores the previous runtime if activation or the final-path test fails.

A version marker, `~/.opencode/.opencode-termux-version`, records the npm package version that prepared the runtime. The launcher compares this marker and the required files with the installed package before deciding whether to reuse the runtime.

## Dependencies checked at launch

The installer checks the following commands and fixed Termux paths:

| Check | Package installed if missing | Why it is needed |
| --- | --- | --- |
| `curl` command | `curl` | Downloads the release archive over HTTPS. |
| `tar` command | `tar` | Extracts the archive. |
| `patchelf` command | `patchelf` | Sets the ELF interpreter for the OpenCode executable. |
| `timeout` command | `coreutils` | Limits the duration of the npm version query. |
| `/data/data/com.termux/files/usr/etc/tls/cert.pem` | `ca-certificates` | TLS certificate bundle path exported by the launcher. |
| `/data/data/com.termux/files/usr/etc/resolv.conf` | `resolv-conf` | Resolver configuration used by the patched musl runtime. |

If any item is missing, `install.js` invokes `pkg install -y` for the corresponding package and verifies the requirements again. A working `pkg` command and reachable Termux repositories are therefore needed when repair requires package installation. The installer reports an error and the launcher stops if a dependency remains missing.

These packages are installed at the Termux environment level. Uninstalling `opencode-termux` does not automatically remove them, because other Termux tools may also depend on them.

## Runtime files, verification, and recovery

### Where things are stored

| Path | Purpose |
| --- | --- |
| npm global prefix | Launcher, `install.js`, package metadata, and checksum metadata installed by npm. |
| `~/.opencode/` | Runtime files managed by this package: OpenCode binary, musl loader/libraries, C++ support libraries, and version marker. |
| `~/.opencode/.opencode-termux-version` | Runtime/package version marker. |
| `$XDG_CACHE_HOME/opencode-termux/last-update-check` | Timestamp for a successful, valid npm version check when `XDG_CACHE_HOME` is set. |
| `~/.cache/opencode-termux/last-update-check` | Same update-check timestamp when `XDG_CACHE_HOME` is not set. |
| `~/.config/opencode/` | OpenCode configuration location; separate from this project's managed runtime directory. |
| `~/.local/share/opencode/auth.json` | OpenCode provider credentials/API keys and authentication data; managed by OpenCode, not by this wrapper. |

### API keys and provider credentials

The launcher in `bin/opencode` passes the supplied arguments to the packaged OpenCode executable; this repository does not implement its own API-key storage or credential-management system. OpenCode's provider documentation identifies the credentials file as:

```text
~/.local/share/opencode/auth.json
```

Use OpenCode's `/connect` command to add provider credentials rather than adding keys to this repository's files. The path above is OpenCode's credential storage, not the runtime directory `~/.opencode/` managed by this project. See the [official OpenCode provider documentation](https://opencode.ai/docs/providers).

Treat `auth.json` as sensitive: do not publish it, commit it to a Git repository, or share its contents in issues or screenshots.

### What the checksum does—and does not—prove

The npm package's `release-checksums.json` contains the package version and expected SHA-256 digest of its runtime archive. The installer refuses to proceed if the checksum metadata version differs from `package.json`, if the digest is malformed, or if the downloaded archive's digest does not match.

This checks that the downloaded archive matches the digest distributed in the installed npm package. It does not independently prove that the upstream program is secure or that the npm package itself is trustworthy.

### Repair the runtime without uninstalling

First, try updating the wrapper/runtime package and launching again:

```bash
npm install -g opencode-termux@latest
opencode
```

If the runtime files exist but the version marker is stale, remove only the marker and relaunch:

```bash
rm -f ~/.opencode/.opencode-termux-version
opencode
```

The launcher should then ask the installer to prepare the runtime for the currently installed npm package. This command does not intentionally delete OpenCode configuration in `~/.config/opencode/`.

If the managed runtime is corrupted or incomplete, remove the runtime directory and let the launcher recreate it:

```bash
rm -rf ~/.opencode
opencode
```

**Warning:** the last command permanently deletes the entire `~/.opencode/` directory. Use it only for runtime repair when you understand what is stored there. It does not remove the npm package or `~/.config/opencode/`.

## Automatic package updates

Automatic package checking is enabled by default. The launcher queries npm with:

```bash
timeout 10 npm view opencode-termux version
```

A valid returned version is cached for 24 hours. If a check fails or returns no valid version, no new valid timestamp is written, so a later launch can try again. The check only retrieves the published package version; it does not include your prompts or project files in that query.

When npm reports a different valid version, the launcher attempts to install that exact `opencode-termux` version globally, using `--ignore-scripts --silent`, then re-enters the `opencode` command so the updated launcher and installer are used. If that installation fails, it warns and continues with the already installed version.

Control automatic checking for a launch with an environment variable:

```bash
# Disable the automatic npm version check for this launch
OPENCODE_TERMUX_AUTOUPDATE=0 opencode

# Explicitly enable it (the default)
OPENCODE_TERMUX_AUTOUPDATE=1 opencode

# Check the latest version published to npm
npm view opencode-termux version

# Update manually, without waiting for the automatic check interval
npm install -g opencode-termux@latest
```

The wrapper sets `OPENCODE_DISABLE_AUTOUPDATE=1` for the packaged OpenCode process. This prevents OpenCode's own updater from replacing the compatibility-adjusted runtime with a different upstream binary.

A commit to GitHub is not automatically the same thing as a published npm release. For the latest installable package, check the [npm package page](https://www.npmjs.com/package/opencode-termux) and the [release workflow](https://github.com/C04-wq/opencode-termux/actions/workflows/auto-update.yml).

## Why the compatibility layer is needed

The project starts from OpenCode's official `opencode-linux-arm64-musl.tar.gz` release archive, then builds a small set of runtime libraries and adjusts the executable for Termux.

### Musl loader and shared libraries

Android/Termux is not a conventional glibc-based desktop Linux distribution. The release archive is built for Linux ARM64 with musl. This project packages the musl loader and runtime libraries alongside the executable and starts it explicitly through that loader, passing `~/.opencode/` as the loader-specific library search path. It does not export `LD_LIBRARY_PATH` to child processes. The launcher also clears inherited `LD_PRELOAD` so Termux’s Bionic preload library does not interfere with the packaged musl runtime.

### DNS resolver path

The build script pins a musl source version and verifies its SHA-256 before compiling it for ARM64. It changes musl's resolver configuration path from the conventional `/etc/resolv.conf` to Termux's `/data/data/com.termux/files/usr/etc/resolv.conf`. Without a resolver file at the path expected by the runtime, hostname resolution may fail even when Android itself has connectivity.

### TLS certificate path

The launcher sets `SSL_CERT_FILE` to Termux's `/data/data/com.termux/files/usr/etc/tls/cert.pem`. The dependency check ensures this file exists, installing `ca-certificates` if needed.

### C++ runtime libraries

The build obtains `libgcc_s.so.1` and `libstdc++.so.6` from Alpine's ARM64 packages using Alpine's `apk` package manager and its trusted signing keys. It packages the versioned C++ library under the stable name `libstdc++.so.6.runtime` and creates the `libstdc++.so.6` symbolic link expected by the runtime. The build also checks that the OpenCode binary declares the required shared-library dependencies.

These changes address the environment-specific runtime issues handled by this project; they do not make Android equivalent to a full desktop Linux installation. Some OpenCode features may still depend on platform capabilities outside this compatibility layer.

## Build and release automation

### Package release workflow

The [Build and publish Termux package workflow](.github/workflows/auto-update.yml):

- Runs on a six-hour schedule, on runtime/build changes pushed to `main`, or when manually triggered from `main`. Documentation-only changes do not trigger a package publication.
- Queries the official OpenCode release API for the current release and its ARM64 musl archive SHA-256 digest.
- Determines the package version and checks npm versions against GitHub Releases. It fails closed if any published npm version has no matching release asset, instead of hiding a broken install URL by publishing a newer version.
- Prepares an Alpine chroot on the hosted runner and uses Alpine's package manager to obtain signed ARM64 `libgcc` and `libstdc++` packages. The phone does not need Alpine, and the build does not require Docker.
- Downloads and verifies the official OpenCode archive, builds the pinned musl runtime with the Termux DNS path, assembles the release archive, and calculates its SHA-256 digest.
- Runs syntax checks, inspects archive contents, and performs an `npm pack --dry-run`.
- Commits version/checksum metadata before publication, creates the GitHub Release first, downloads that exact asset again to verify its digest, and only then publishes the npm package. If release creation succeeds but npm publication fails, a later run can resume from that exact release asset instead of rebuilding it. If npm exists but its release is missing, automation stops for manual restoration of the exact archive.

The workflow serializes publishing jobs to avoid concurrent releases and refuses to publish from a non-`main` branch. A relevant runtime/build push to `main` forces a new package revision for the current upstream version; custom revisions use the next unused `-1`, `-2`, and so on suffix. It fails when the upstream digest is missing or when a published npm version lacks its corresponding GitHub Release.

### Toolchain maintenance and validation

- [Toolchain update workflow](.github/workflows/toolchain-updates.yml) checks Alpine's official stable-branch information, validates a candidate build, and opens or updates a reviewable pull request for a new pin; it never pushes the change directly to `main`.
- `scripts/check-toolchain-updates.mjs` discovers the current stable Alpine branch. The musl version and digest are separately pinned in `scripts/build-android-release.sh`; the musl pin is not silently changed by the Alpine update check.
- [Validation workflow](.github/workflows/validate.yml) checks JavaScript and shell syntax, validates version/checksum metadata, checks build assumptions, and runs an npm packaging dry run.
- Dependabot is configured to check npm dependencies and GitHub Actions weekly.

To determine whether a release actually published, inspect the relevant [GitHub Actions run](https://github.com/C04-wq/opencode-termux/actions/workflows/auto-update.yml) and the [npm package versions](https://www.npmjs.com/package/opencode-termux).

## Troubleshooting

Use these checks before changing or deleting files:

```bash
# Confirm Node is installed and running as ARM64
node --version
node -p 'process.arch'

# Confirm the npm package and version
npm list -g opencode-termux --depth=0
npm view opencode-termux version

# Confirm the runtime starts
opencode --version

# Confirm the required Termux packages are present
command -v pkg curl tar patchelf timeout
test -s /data/data/com.termux/files/usr/etc/tls/cert.pem && echo "TLS certificate bundle exists"
test -s /data/data/com.termux/files/usr/etc/resolv.conf && echo "Resolver file exists"
```

### Direct execution of the managed binary fails

Always start OpenCode with the installed `opencode` command, for example `opencode --version`. Do not run `~/.opencode/opencode` directly as a troubleshooting shortcut. The launcher removes an inherited `LD_PRELOAD` (which can load Termux's `libtermux-exec-ld-preload.so` into the separately packaged musl runtime), sets the runtime library and certificate paths, and starts the binary through the bundled musl loader. Bypassing the launcher skips that compatibility setup and can produce misleading dynamic-linker or relocation errors.

If `opencode --version` still fails, capture the exact error from that command and include it in a bug report; do not copy individual system libraries into `~/.opencode/` or bypass the runtime checks.

### `opencode: command not found`

1. Check that npm installation completed: `npm list -g opencode-termux --depth=0`.
2. Check npm's global executable directory with `npm bin -g` if your npm version supports that command, or inspect `npm prefix -g`.
3. Ensure the global npm executable directory is included in `PATH`, then open a new Termux shell and try again.
4. If the package is absent, reinstall it with `npm install -g opencode-termux`.

### Unsupported architecture or Node errors

The installer supports ARM64 only. Check `node -p 'process.arch'`; it must print `arm64`. This project does not support x86_64, 32-bit ARM, or other Node architecture values.

### Dependency setup errors

If the output says that dependencies could not be installed or that `pkg` is missing:

1. Confirm you are running inside Termux, not a different Android shell or a generic Linux environment.
2. Run `pkg update` and resolve any repository/network errors shown by Termux.
3. Check the relevant command/path from the dependency table above.
4. Run `opencode` again. The installer rechecks prerequisites each time.

Do not assume a dependency installed merely because `pkg` ran; the installer verifies the commands and files again and exits if any are still missing.

### Download, HTTP, or checksum errors

- Confirm the device has working internet and GitHub Releases is reachable.
- Retry after transient network failures; the download command uses HTTPS and retries.
- Update the npm package with `npm install -g opencode-termux@latest` in case the installed package metadata and available release are out of sync.
- If the checksum still fails, stop and report the error. Do not disable or bypass checksum verification; the installer intentionally rejects an archive that does not match the package's expected digest.

### `package checksum metadata does not match package.json`

This means the package's embedded version metadata is inconsistent. Install a coherent published package again:

```bash
npm install -g opencode-termux@latest
```

If it persists, report the installed version from `npm list -g opencode-termux --depth=0` and the exact error to the repository's issue tracker. Do not manually edit the checksum file to make the error disappear.

### DNS or TLS errors

Check that the resolver file and certificate bundle exist using the commands above. If either is missing, run `pkg install resolv-conf ca-certificates` and then retry. The runtime's musl resolver is built to use Termux's resolver path; changing unrelated Android DNS settings is not the first repair step.

### OpenCode starts but network access fails

First distinguish a Termux/runtime DNS or TLS error from an OpenCode provider/authentication error. Check the resolver and certificate paths above, then retry. If the error names an AI provider, model, API key, or account, configure that provider through OpenCode's normal supported settings; this wrapper does not supply provider credentials or bypass authentication.

### Automatic update does not run immediately

The version-check timestamp suppresses another valid check for 24 hours. Install manually with `npm install -g opencode-termux@latest` to update immediately. If the npm query fails or does not return a valid version string, the launcher keeps using the installed version.

### New source code is visible on GitHub but npm still shows an older version

The source changes have to pass the release workflow and be published before `npm install` can retrieve them. Check the workflow run and npm package page. A successful commit or a failed earlier workflow run alone does not establish that the latest release is available.

### What to include in a bug report

Include the exact error text and the output of:

```bash
node --version
node -p 'process.arch'
npm list -g opencode-termux --depth=0
opencode --version
```

Do not post API keys, access tokens, credentials, private prompts, or private project contents.

## Uninstalling

### Remove the package and its managed runtime

Run:

```bash
npm uninstall -g opencode-termux
rm -rf ~/.opencode
```

- `npm uninstall -g opencode-termux` removes the globally installed npm package, including the `opencode` launcher and its installer script.
- `rm -rf ~/.opencode` removes the runtime files managed by this project.

The second command is destructive. Check the directory before removing it if you have placed any files there yourself. These commands do not remove `~/.config/opencode/`, which may contain OpenCode settings and other configuration.

### Also remove OpenCode configuration (optional)

Only if you deliberately want to delete the configuration too:

```bash
rm -rf ~/.config/opencode
```

Review the directory first if you want to preserve settings. Removing the package does not require deleting configuration.

### What uninstall does not remove

The package does not automatically uninstall Termux packages such as `curl`, `tar`, `patchelf`, `coreutils`, `ca-certificates`, or `resolv-conf`. They are normal Termux packages and may be needed by other software. Remove them manually only if you know no other tool needs them.

The uninstall commands above do not delete your Termux home directory or uninstall Termux itself.

## Repository map

| Path | Responsibility |
| --- | --- |
| `bin/opencode` | Command entry point: checks prerequisites and runtime files, performs the optional npm version check, sets the runtime environment, and launches OpenCode. |
| `install.js` | Checks/installs prerequisites; validates package metadata; downloads, hashes, extracts, patches, tests, and activates the runtime. |
| `package.json` | npm package metadata, package version, Node engine requirement, and `opencode` command mapping. |
| `release-checksums.json` | Package version and expected SHA-256 digest of the corresponding runtime archive. |
| `scripts/build-android-release.sh` | Builds the Termux-compatible ARM64 archive from the official OpenCode binary, a pinned musl source, and Alpine runtime libraries. |
| `scripts/setup-alpine-chroot.sh` | Prepares the Alpine chroot used by hosted builds without Docker. |
| `scripts/check-toolchain-updates.mjs` | Checks the official Alpine release page for stable-branch changes. |
| `.github/workflows/auto-update.yml` | Builds and publishes npm/GitHub releases. |
| `.github/workflows/toolchain-updates.yml` | Checks and validates toolchain updates. |
| `.github/workflows/validate.yml` | Runs static checks and package validation. |
| `.github/dependabot.yml` | Schedules weekly dependency checks for npm and GitHub Actions. |

## Limitations and security notes

- This package targets Termux on ARM64/aarch64, not all Android architectures or Linux distributions.
- Initial setup and runtime repair need network access. An already-prepared runtime can be reused without downloading it again, but dependency installation and npm update checks may need connectivity.
- The wrapper does not provide AI models, API keys, paid service access, or authentication bypasses. Configure providers using OpenCode's normal mechanisms.
- SHA-256 verification detects a runtime archive that differs from the digest embedded in the installed npm package; it is not a general security audit.
- The automatic update check queries npm for the package version. OpenCode itself may make network requests to the AI providers and other services you configure.
- Runtime files under `~/.opencode/` are managed by this project. Replacing individual files manually can break the runtime/version assumptions.
- Do not run destructive repair or uninstall commands against paths you have not checked.

## License

[MIT](LICENSE)
