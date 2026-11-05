# opencode-termux

Run OpenCode on Android through Termux, installed directly from this Git repository with Bash. **npm and Node.js are not required.**

## Requirements

- Android with Termux on ARM64/aarch64.
- Internet access.
- Git, curl, tar, sha256sum, Termux CA certificates, and resolver configuration. The installer checks for required tools and uses Termux pkg to install missing dependencies.

## Install from GitHub

    pkg update
    pkg install git
    git clone https://github.com/C04-wq/opencode-termux.git
    cd opencode-termux
    bash install.sh

Then launch:

    opencode

The installer downloads the ARM64 runtime archive for the version in release-checksums.json, verifies its SHA-256, checks the runtime files, tests --version, and installs under $PREFIX/lib/opencode-termux. The launcher is installed at $PREFIX/bin/opencode.

## Updates

Every interactive launch of `opencode` quietly checks the `main` branch metadata on GitHub. If a newer version is available, it displays two English options: `1) Install update now` or `2) Wait for the next version`. Choosing option 1 updates and then launches OpenCode; choosing option 2 launches the currently installed version. If there is no newer version, OpenCode starts normally without an update message. If GitHub cannot be reached, the current version starts normally.

You can also update manually at any time:

    opencode-termux-update

The updater runs `git pull --ff-only` in the cloned repository and reruns the installer. Local changes that prevent a fast-forward are not overwritten. Keep the clone in its original location because the launcher and updater refer to it.

## Verify

    opencode --version
    opencode --help

## Uninstall

From the cloned repository:

    bash uninstall.sh

The uninstaller removes only the managed runtime and launchers. It preserves ~/.config/opencode, ~/.local/share/opencode, sessions, and provider credentials. It does not remove Termux packages that other applications may use. Delete the cloned repository manually if you also want to remove the installer source.

## Security and compatibility

- ARM64/aarch64 only.
- Bash installer; no npm, Node.js, or patchelf.
- SHA-256 is checked before extraction or execution.
- The runtime is tested before and after activation.
- The launcher clears inherited LD_PRELOAD to avoid the Termux preload/musl conflict.
- The launcher uses the bundled musl loader and Termux CA certificate bundle.
- OpenCode's self-updater is disabled to protect the Termux-adjusted runtime.
- API access is not included; configure a supported provider inside OpenCode.

## Development

    bash -n install.sh uninstall.sh

## License

MIT
