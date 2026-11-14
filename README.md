# opencode-termux

<p align="center">
  <img src="./opencode-logo.svg" alt="OpenCode logo" width="72" height="90">
</p>

<p align="center">
  <strong>Run OpenCode natively on Android through Termux.</strong><br>
  Install and maintain it directly from this Git repository with Bash.
</p>


Run OpenCode natively on Android through Termux. Install and maintain it directly from this Git repository with Bash. **Node.js and npm are not required on your Android device.**

## Screenshots

The following screenshots are stored in this repository and displayed directly below.

<table>
  <tr>
    <td width="50%" align="center">
      <img src="./screenshots/screenshot-1.png" alt="OpenCode running in Termux — screenshot 1" width="100%">
    </td>
    <td width="50%" align="center">
      <img src="./screenshots/screenshot-2.png" alt="OpenCode running in Termux — screenshot 2" width="100%">
    </td>
  </tr>
  <tr>
    <td width="50%" align="center">
      <img src="./screenshots/screenshot-3.png" alt="OpenCode running in Termux — screenshot 3" width="100%">
    </td>
    <td width="50%" align="center">
      <img src="./screenshots/screenshot-4.png" alt="OpenCode running in Termux — screenshot 4" width="100%">
    </td>
  </tr>
</table>

## Status

- ARM64/aarch64 support for Android with Termux.
- Tested on a real Android device: OpenCode launches and its interactive terminal interface and background server work correctly.
- The packaged runtime is built from official stable OpenCode releases.
- Automatic update discovery and a dedicated updater are included.

## Requirements

- Android with [Termux](https://termux.dev/) on ARM64/aarch64.
- Internet access.
- Git, curl, tar, sha256sum, Termux CA certificates, and resolver configuration. The installer checks for required tools and uses Termux `pkg` to install missing dependencies.

## Install

Open Termux and run:

```bash
pkg update
pkg install git
git clone https://github.com/C04-wq/opencode-termux.git
cd opencode-termux
bash install.sh
```

Then start OpenCode:

```bash
opencode
```

The installer reads the pinned version and SHA-256 digest from `release-checksums.json`, downloads the corresponding ARM64 runtime archive from this repository's GitHub Releases, verifies its integrity, checks the required runtime files, tests it, and installs it under `$PREFIX/lib/opencode-termux`. The launcher is installed at `$PREFIX/bin/opencode`.

## Updates

### Automatic update discovery

Every interactive launch of `opencode` quietly checks the version metadata on this repository's `main` branch.

When a newer stable version has been built and published for Termux, the launcher displays a small two-option menu:

- **Install update now** — updates the repository clone, installs the new verified runtime, and starts OpenCode.
- **Wait for the next version** — starts the currently installed version without updating.

Use the Up/Down arrow keys to select an option and press Enter to confirm. If no newer version is available, OpenCode starts normally. If GitHub cannot be reached, the current installation still starts; an update check never intentionally blocks normal startup.

This is automatic **update detection**, not a forced background installation: you choose when to install the update.

### Manual update

You can update at any time with:

```bash
opencode-termux-update
```

The updater performs a fast-forward-only Git pull in the original cloned repository and reruns the installer. The installer downloads the version pinned by the repository metadata and verifies its SHA-256 before installation. Local Git changes that prevent a fast-forward are not overwritten.

**Keep the cloned repository in its original location.** The installed launcher and updater use that path to find the installer and update metadata.

### New OpenCode versions and major releases

The release workflow checks official stable OpenCode releases across **all major version numbers**, selects the highest stable semantic version, and builds a Termux package for it when the required official ARM64 musl archive and verifiable upstream checksum are available.

This is designed to follow major-version transitions too, for example from 1.x to 2.x and later to 3.x, without hard-coding the project to a particular major version. A new upstream release is not installed on your phone until the corresponding Termux release has been built and published and you accept the update.

If the newest stable upstream release does not provide the required ARM64 musl archive or a verifiable checksum, the workflow fails rather than silently packaging an older version. Draft and prerelease versions are excluded.

## Verify

Check the installed version and available commands:

```bash
opencode --version
opencode --help
```

## Troubleshooting

### `opencode: command not found`

Run the installer again from the root of the cloned repository, then refresh Bash's
command cache:

```bash
bash install.sh
hash -r
opencode --version
```

A stale command cache is the usual cause right after an install or after switching
shells; `hash -r` alone fixes that case.

### Migrating from the npm package

`npm install -g opencode-termux` is the legacy installation method. It required
Node.js, npm, and `patchelf` on the device and is the source of the `spawnSync pkg
EACCES`, `spawnSync patchelf EACCES`, and `Could not find a PHDR` errors reported in
[#4](https://github.com/C04-wq/opencode-termux/issues/4),
[#20](https://github.com/C04-wq/opencode-termux/issues/20), and
[#21](https://github.com/C04-wq/opencode-termux/issues/21).

The current installer uses Bash and ships a prebuilt runtime, so Node.js, npm, and
`patchelf` are no longer needed. Remove the legacy package and install from source:

```bash
npm uninstall -g opencode-termux
git clone https://github.com/C04-wq/opencode-termux.git
cd opencode-termux
bash install.sh
```

If a clone already exists, update it instead of cloning again:

```bash
git -C opencode-termux pull --ff-only
cd opencode-termux
bash install.sh
```

### `spawnSync pkg EACCES` or `spawnSync patchelf EACCES`

These errors come from the legacy npm package. Follow
[Migrating from the npm package](#migrating-from-the-npm-package) to switch to the
Bash installer.

### `Could not find a PHDR: broken executable?`

This error was reported when older npm-installed runtimes prepared the bundled musl
runtime with `patchelf` on the device. Follow
[Migrating from the npm package](#migrating-from-the-npm-package) to switch to the
Bash installer. If the error persists after a Bash install, open an issue with your
Android version, the output of `uname -m`, and the full installer output.

### Installer download fails or `curl` rejects an option

Update the Termux packages the installer downloads with:

```bash
pkg update
pkg install git curl tar coreutils ca-certificates
```

The installer checks for `git`, `curl`, `tar`, and `sha256sum` (from `coreutils`)
and installs any that are missing, along with `ca-certificates` and `resolv-conf`
when Termux lacks them. If downloads still fail, verify connectivity before
retrying:

```bash
curl -I https://github.com
```

### Shell or search tools hang inside OpenCode

Older packages exported the bundled musl loader through `LD_PRELOAD`, which crashed
Termux child processes. The current launcher clears `LD_PRELOAD` before starting
OpenCode. If you installed with npm, follow
[Migrating from the npm package](#migrating-from-the-npm-package). If you installed
with the Bash installer, update to the latest release:

```bash
opencode-termux-update
```

## Uninstall

From the cloned repository:

```bash
bash uninstall.sh
```

The uninstaller removes only the runtime and launchers managed by this project. It preserves your OpenCode configuration, sessions, provider credentials, and user data in:

- `~/.config/opencode`
- `~/.local/share/opencode`

It does not remove Termux packages that other applications may use. Delete the cloned repository manually if you also want to remove the installer source.

## Compatibility and security

- **Architecture:** ARM64/aarch64 on Android with Termux.
- **Device dependencies:** Bash, Git, curl, tar, and checksum utilities; no Node.js, npm, or `patchelf` is required on the phone.
- **Integrity:** the installer verifies the downloaded archive against the SHA-256 value tracked in `release-checksums.json` before extraction or execution.
- **Runtime validation:** required files are checked and the OpenCode binary is tested before and after activation.
- **Termux environment:** the launcher clears inherited `LD_PRELOAD` to avoid conflicts between Termux and the bundled musl runtime, configures the Termux CA certificate bundle, and supplies the bundled C++ libraries through `LD_LIBRARY_PATH`.
- **Background server:** the OpenCode ELF interpreter (`PT_INTERP`) points to the bundled musl loader in the installed runtime. The launcher executes the binary directly so that `/proc/self/exe` remains correct when OpenCode starts its background server.
- **Self-updates:** OpenCode's own updater is disabled so it cannot replace the Termux-adjusted runtime outside this project's verified installation process.
- **Provider access:** API access is not included. Configure a supported provider from within OpenCode.

## Development and release automation

GitHub Actions validate the installer and build ARM64 Termux release archives. The scheduled release workflow checks upstream stable releases every six hours, resolves the highest stable semantic version across all major versions, verifies the required upstream ARM64 musl archive and checksum, builds the Termux runtime, and publishes the archive and checksum metadata.

Node.js is used by hosted CI scripts only; it is not needed on the Android device.

Run the local Bash syntax checks with:

```bash
bash -n install.sh uninstall.sh
```

## License

MIT
