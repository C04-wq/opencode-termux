# OpenCode Android/Termux parity audit

This port is built from the exact official `anomalyco/opencode` source commit recorded in `tools/supply-chain-lock.json`. It does not substitute another OpenCode fork or prebuilt third-party OpenCode executable. Android-specific compatibility changes are applied by the repository's patch scripts and native build pipeline.

This document separates source inclusion from runtime verification. A feature being present in the JavaScript bundle does not prove that every Android runtime path works.

## Architecture and component matrix

| Component | ARM64 | x86_64 | Current status |
|---|---|---|---|
| Official OpenCode CLI, commands and application logic | Bundled | Bundled | Same pinned upstream source; Android patches applied |
| HTTP server, WebSocket API and web application assets | Bundled | Bundled | Runtime integration coverage is incomplete |
| TUI and OpenTUI renderer | Bionic native build | Bionic native build | Build/ELF checks exist; full interactive device coverage remains |
| Bun PTY native library (`librust_pty_*.so`) | Built | Built | This is a shared library, not the process daemon |
| Official persistent process daemon (`opencode-pty`) | Source-build implemented | Source-build implemented | Built from upstream `packages/process-daemon` with pinned Ghostty; CI and Android IPC verification pending |
| Ghostty terminal VT engine used by the daemon | Statically linked from the pinned upstream Ghostty revision | Statically linked from the pinned upstream Ghostty revision | Android target requires the NDK and a supported Zig toolchain |
| File watching (`@parcel/watcher`) | Source-built | Source-built | Rebuilt from the exact upstream package source for both Android targets; real file-change behavior still needs device coverage |
| FFF search/index backend | Source-build path added | Source-build path added | Rebuilt from the exact FFF Rust source version pinned by official OpenCode; CI must still validate Android compilation and 16 KB ELF alignment |
| Scalar/Swagger API reference UI | Stubbed | Stubbed | API server remains; embedded API-reference UI assets are currently omitted |
| Shell integration, SQLite storage/migrations, providers, authentication, MCP, LSP and plugins | Upstream JS source bundled | Upstream JS source bundled | Broad feature regression coverage on Android is still required |
| Desktop GUI application | Not ported | Not ported | Separate desktop product; not part of the Termux CLI/server runtime |

## Remaining parity work

### Native runtime
- Pass the Android cross-build of the official `opencode-pty` daemon for both Rust targets in CI.
- Verify the daemon's Android ELF interpreter, 64-bit architecture, Bionic dependencies and executable permissions.
- Run the daemon's upstream Rust test suite on Linux CI and compile its test harnesses for both Android targets.
- On real Termux, verify daemon startup, ownership handshake, IPC, PTY creation, resize, output replay, process exit, cleanup and restart.
- Verify 16 KB Android page-size compatibility for every shipped ELF executable and shared object, not only architecture and glibc linkage.
- Test terminal rendering, keyboard input, mouse/paste behavior, Unicode width, truecolor, alternate screen, resize, clipboard and shell integration on both architectures.

### Feature integration
- Restore or replace the currently stubbed Scalar/Swagger API-reference assets without removing the upstream HTTP API.
- Verify FFF search/index semantics, watcher integration and performance on both Android architectures after the source-built backend passes CI.
- Exercise `opencode serve`, `opencode web`, remote clients, HTTP authentication, WebSocket upgrades, OAuth callbacks and browser-based login flows on Android.
- Run provider/authentication regression tests for API keys, OAuth refresh, model discovery, usage limits and credential persistence.
- Exercise MCP stdio/SSE/HTTP transports, LSP startup/shutdown, plugins, skills, shell commands, file edits, search, git tools, images and session persistence.
- Verify SQLite migrations, backups, concurrent access, interrupted updates and recovery on Termux storage.
- Test process and file-watcher behavior when the app is backgrounded, Android kills child processes, or the device sleeps.

### Updates and releases
- The six-hour upstream watcher prepares a draft candidate PR and dispatches dual-architecture validation. No workflow auto-merges candidates or creates release tags; a maintainer must review and merge the candidate and create the release tag manually. The tag-triggered workflow then runs the normal checksum-verified release build.
- If candidate CI fails, the PR remains a draft and the six-hour watcher retries validation. Passing CI does not approve or merge the candidate automatically.
- The official OpenCode updater remains enabled. Its Termux integration reads this repository’s release metadata, tracks package revision tags as well as the upstream OpenCode version, and invokes the checksum-verifying installer. No separate six-hour launcher timer or silent launcher update is installed.
- These automation paths still require successful GitHub Actions verification and real-device tests of rollback, interrupted downloads, concurrent launches and post-update recovery.
- Verify that `opencode update`, `opencode upgrade` and the TUI `/update` flow all install the same verified ARM64/x86_64 release and never bypass checksum validation.

## Acceptance criteria

A release must not be called 100% equivalent until all of the following are true:

1. Both architectures build from the same pinned official OpenCode commit and the exact locked native dependencies.
2. Both archives contain every required executable, shared library, JavaScript asset, web asset and provenance marker.
3. ELF checks prove the correct machine, Android interpreter, Bionic linkage and supported page alignment; no glibc runtime dependency is present.
4. Upstream Rust daemon tests, repository static/contract tests, archive validation, installer/update tests and server/TUI smoke tests pass.
5. Automated CI/emulation tests cover ARM64 and x86_64 installation, CLI/server startup, TUI/PTY daemon IPC, authentication, file watching, updates and recovery. Real-device checks are supplementary; any Android-kernel behavior not reproducible in CI must be documented explicitly.
6. Every intentionally omitted desktop-only or Android-incompatible feature is documented as a platform limitation rather than silently treated as parity.

Until these criteria pass, the project is an official-source Android port with known parity gaps, not a verified 100% drop-in equivalent.
