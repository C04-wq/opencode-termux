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
| Official persistent process daemon (`opencode-pty`) | New cross-build path | New cross-build path | Being added from upstream `packages/process-daemon`; must pass CI and real-device IPC tests before release |
| Ghostty terminal VT engine used by the daemon | Statically linked from the pinned upstream Ghostty revision | Statically linked from the pinned upstream Ghostty revision | Android target requires the NDK and a supported Zig toolchain |
| File watching (`@parcel/watcher`) | Android module | Android source build | Build checks exist; real file-change behavior still needs device coverage |
| FFF search/index backend | Source-built | Source-built | Rebuilt from the exact FFF Rust source version pinned by official OpenCode; 16 KB ELF alignment is checked |
| Scalar/Swagger API reference UI | Stubbed | Stubbed | API server remains; embedded API-reference UI assets are currently omitted |
| Shell integration, SQLite storage/migrations, providers, authentication, MCP, LSP and plugins | Upstream JS source bundled | Upstream JS source bundled | Broad feature regression coverage on Android is still required |
| Desktop GUI application | Not ported | Not ported | Separate desktop product; not part of the Termux CLI/server runtime |

## Remaining parity work

### Native runtime
- Finish and pass the Android cross-build of the official `opencode-pty` daemon for both Rust targets.
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
- The six-hour upstream watcher currently prepares a candidate PR and CI run; it does not yet automatically merge and publish every passing stable upstream release.
- Release publication is tag-driven. Automatic candidate approval/merge/tagging still needs to be implemented with strict CI gates and immutable source/build provenance.
- The installed device currently relies on the project updater/installer flow. A fully unattended device-side update policy, rollback and recovery behavior still need to be defined and tested.
- Verify that the interactive OpenCode update path and `opencode-termux update` both install the same verified ARM64/x86_64 release and never bypass checksum validation.

## Acceptance criteria

A release must not be called 100% equivalent until all of the following are true:

1. Both architectures build from the same pinned official OpenCode commit and the exact locked native dependencies.
2. Both archives contain every required executable, shared library, JavaScript asset, web asset and provenance marker.
3. ELF checks prove the correct machine, Android interpreter, Bionic linkage and supported page alignment; no glibc runtime dependency is present.
4. Upstream Rust daemon tests, repository static/contract tests, archive validation, installer/update tests and server/TUI smoke tests pass.
5. Real Termux tests pass on ARM64 and x86_64 for TUI, persistent PTY/daemon, server, authentication, file watching, updates and recovery.
6. Every intentionally omitted desktop-only or Android-incompatible feature is documented as a platform limitation rather than silently treated as parity.

Until these criteria pass, the project is an official-source Android port with known parity gaps, not a verified 100% drop-in equivalent.
