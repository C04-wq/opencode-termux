import fs from "node:fs";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";

const lock = JSON.parse(fs.readFileSync("tools/supply-chain-lock.json", "utf8"));
const version = lock.current;
const packageTag = spawnSync("python3", ["tools/ocver.py", "tag"], { encoding: "utf8" });
assert.equal(packageTag.status, 0, "release tag helper must succeed");
assert.match(packageTag.stdout.trim(), new RegExp("^v" + version.replaceAll(".", "\\.") + "(-[1-9][0-9]*)?$"));
if (version === "2.3.2") assert.notEqual(packageTag.stdout.trim(), "v2.3.2", "the native rebuild must not collide with the existing legacy v2.3.2 release");
assert.ok(lock.opencode[version], "current OpenCode version must exist in the source lock");
assert.equal(lock.android_ndk_version, "30.0.16248370", "Android NDK must be pinned");
assert.match(lock.opencode[version].commit, /^[a-f0-9]{40}$/);
assert.ok(lock.opencode[version].bun_version);
assert.ok(lock.opencode[version].opentui_version);
assert.match(lock.bun_pty.commit, /^[a-f0-9]{40}$/);
assert.ok(lock.opentui[lock.opencode[version].opentui_version]);

const build = fs.readFileSync("scripts/ci/build-opencode-bundle.sh", "utf8");
for (const token of [
  "https://github.com/anomalyco/opencode.git",
  "tools/supply-chain-lock.json",
  "tools/patch-opencode-source.py",
  "tools/patch-opencode-bundle.py",
  "tools/patch-opentui-ffi.py",
  "tools/patch-opentui-loader.py",
  "tools/patch-fff-android.py",
  "scripts/ci/build-rust-pty-android.sh",
  "scripts/ci/build-opencode-pty-android.sh",
  "artifacts/bundle/"
]) assert.ok(build.includes(token), "native build script missing " + token);
assert.ok(build.includes("--filter 'opencode'"), "native typecheck must install root workspace development tools");
assert.ok(build.includes('export PATH="$work/host/bun-linux-x64:$PATH"'), "verified host Bun must be available to lifecycle subprocesses");
assert.ok(build.includes('TARGET_ARCH="${TARGET_ARCH:-aarch64}"'), "runtime bundle builder must select an explicit supported architecture");
assert.ok(build.includes('OPENCODE_ARCH="x64"'), "x86_64 must map to OpenCode x64 target naming");
assert.ok(build.includes("build-parcel-watcher-android.sh"), "both Android bundles must use the Bionic watcher source build");
assert.ok(build.includes("scripts/ci/build-fff-android.sh"), "both architectures must compile FFF from its pinned Rust source");
assert.ok(!build.includes("fff: disabled for x86_64"), "x86_64 must not silently disable the official FFF backend");
assert.ok(build.includes('install -m 0755 "$pty_daemon" "$out/lib/opencode/opencode-pty"'), "the official daemon must be packaged in the runtime archive");
assert.ok(build.includes('opencode-pty.required'), "new archives must mark the daemon as required");
const supplyChain = JSON.parse(fs.readFileSync("tools/supply-chain-lock.json", "utf8"));
assert.equal(supplyChain.process_daemon.package, "opencode-pty");
assert.match(supplyChain.process_daemon.version, /^\d+\.\d+\.\d+/);
assert.match(supplyChain.process_daemon.ghostty_commit, /^[a-f0-9]{40}$/);
assert.deepEqual(supplyChain.process_daemon.android_targets, ["aarch64-linux-android", "x86_64-linux-android"]);
assert.equal(supplyChain.fff.package, "@ff-labs/fff-bun");
assert.match(supplyChain.fff.version, /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/);
assert.match(supplyChain.fff.commit, /^[a-f0-9]{40}$/);
assert.deepEqual(supplyChain.fff.android_targets, ["aarch64-linux-android", "x86_64-linux-android"]);
const fffBuild = fs.readFileSync("scripts/ci/build-fff-android.sh", "utf8");
for (const token of [
  "crates/fff-c/Cargo.toml",
  "cargo build --locked --release",
  "aarch64-linux-android",
  "x86_64-linux-android",
  "CMAKE_TOOLCHAIN_FILE",
  "max-page-size=16384",
  "common-page-size=16384",
  "readelf -lW"
]) assert.ok(fffBuild.includes(token), "official FFF Android build missing " + token);
const fffPatch = fs.readFileSync("tools/patch-fff-android.py", "utf8");
assert.ok(fffPatch.includes('choices=("aarch64", "x86_64")'), "FFF patch must support both Android architectures");
assert.ok(fffPatch.includes('"x86_64": ("x64", "x64")') && fffPatch.includes('package_name = f"@ff-labs/fff-bin-android-{package_arch}"'), "FFF x86_64 package must be selected");
const daemonBuild = fs.readFileSync("scripts/ci/build-opencode-pty-android.sh", "utf8");
for (const token of [
  "packages/process-daemon/Cargo.toml",
  "packages/process-daemon/Cargo.lock",
  "cargo test --locked",
  "cargo build --locked --release",
  "cargo test --locked --no-run",
  "aarch64-linux-android",
  "x86_64-linux-android",
  "readelf -l",
  "ANDROID_NDK_HOME",
  "ANDROID_NDK_ROOT",
  "/system/bin/linker64",
  "libc\\.so\\.6",
  "max-page-size=16384",
  "common-page-size=16384",
  "readelf -lW"
]) assert.ok(daemonBuild.includes(token), "official opencode-pty Android build missing " + token);
const bundlePatch = fs.readFileSync("tools/patch-opencode-bundle.py", "utf8");
assert.ok(bundlePatch.includes('choices=("aarch64", "x86_64")'), "bundle patcher must expose only the official 64-bit architecture targets");
assert.ok(bundlePatch.includes('opencode_arch = "arm64" if args.target_arch == "aarch64" else "x64"'), "bundle patcher must map Termux architectures to OpenCode target names");
assert.ok(bundlePatch.includes('arch: "{opencode_arch}", abi: "android"'), "bundle patcher must register the selected Android architecture");

const pty = fs.readFileSync("scripts/ci/build-rust-pty-android.sh", "utf8");
assert.ok(pty.includes("EXPECTED_COMMIT"), "bun-pty source commit must be pinned and verified");
assert.ok(pty.includes("tools/ocver.py bunpty commit"));
assert.ok(pty.includes("x86_64-linux-android"), "PTY cross-build must map x86_64 to the Android Rust target");
assert.ok(pty.includes('portable-pty = { version = "=0.9.0"'), "Android PTY dependency must be exact-pinned");
assert.ok(pty.includes('cargo update --manifest-path "$SRC/rust-pty/Cargo.toml" -p portable-pty --precise "$portable_pty_version"'), "Cargo lock must be updated only to the exact portable-pty pin");
assert.ok(pty.includes("build --locked --release"), "the PTY build must reject unrecorded dependency resolution");
assert.equal(lock.bun_pty.portable_pty, "0.9.0", "portable-pty Android compatibility pin must be exact");

const rustPtyBuild = fs.readFileSync("scripts/ci/build-rust-pty-android.sh", "utf8");
assert.ok(rustPtyBuild.includes("max-page-size=16384"), "bun-pty must be linked for Android 16 KB pages");
assert.ok(rustPtyBuild.includes("common-page-size=16384"), "bun-pty must declare the Android 16 KB common page size");
assert.ok(rustPtyBuild.includes("readelf -lW"), "bun-pty build must inspect ELF page alignment");
const watcherBuild = fs.readFileSync("scripts/ci/build-parcel-watcher-android.sh", "utf8");
for (const token of [
  "x86_64-linux-android",
  "src/linux/InotifyBackend.cc",
  "src/unix/legacy.cc",
  "NAPI_VERSION=4",
  "NODE_GYP_MODULE_NAME=watcher",
  "-fvisibility=default",
  "-Wl,--export-dynamic",
  "napi_register_module_v1",
  "max-page-size=16384",
  "readelf -lW",
  "readelf -h",
  "glibc-linked dependency found"
]) assert.ok(watcherBuild.includes(token), "Android watcher cross-build missing " + token);
assert.ok(watcherBuild.includes("unsupported TARGET_ARCH"), "watcher builder must reject unsupported targets");
const smoke = fs.readFileSync("scripts/smoke-test-runtime-archive.sh", "utf8");
assert.ok(smoke.includes("export TARGET_ARCH"), "archive smoke test must pass the selected architecture to the validator");
assert.ok(smoke.includes("16#$alignment < 16384"), "all Android ELF modules must satisfy 16 KB page alignment");
assert.ok(smoke.includes("readelf -lW"), "archive smoke test must inspect ELF program headers for page alignment");
for (const token of [
  "N-API constructor registration import",
  "napi_module_register",
  ".init_array",
  "napi_register_module_v1",
  "node_api_module_get_api_version_v1"
]) assert.ok(smoke.includes(token), "archive smoke test must validate watcher N-API registration: " + token);


const sourcePatch = fs.readFileSync("tools/patch-opencode-source.py", "utf8");
assert.ok(sourcePatch.includes("C04-wq/opencode-termux"), "native updater must target this repository");
assert.ok(sourcePatch.includes("raw.githubusercontent.com/C04-wq/opencode-termux/main/install.sh"), "native updater must use the current installer");
assert.ok(sourcePatch.includes("release-checksums.json"), "native updater must use the installer's pinned metadata");
assert.ok(sourcePatch.includes('exec(["bash", installer], "4 hours")'), "native updater must invoke the Bash installer with Bash");
assert.ok(sourcePatch.includes("actualVersion !== version"), "native and APT update paths must verify the installed version");
assert.ok(sourcePatch.includes('item.abi !== "android"'), "Android targets must never resolve a glibc PTY asset");
assert.ok(sourcePatch.includes("packages/process-daemon/src/service.rs"), "Android port must preserve official foreground-process detection");
assert.ok(sourcePatch.includes('#[cfg(any(target_os = "linux", target_os = "android"))]'), "Android process-daemon cfg must include Linux /proc behavior");
assert.ok(sourcePatch.includes("isCurlMethod(method)"), "curl installation detection must remain type-safe in the upstream uninstall patch");
assert.ok(!sourcePatch.includes("'    if (prefix) return\\n'"), "Termux must not suppress detection of legacy package-managed installations");
assert.ok(!sourcePatch.includes('exec(["sh", installer]'), "Bash installer must never be invoked through sh");

const opentuiPatch = fs.readFileSync("tools/patch-opentui-android.py", "utf8");
assert.ok(opentuiPatch.includes("builtin.abi == .android"), "Android OpenTUI must avoid glibc-only pthread_tryjoin_np");
assert.ok(opentuiPatch.includes("thread.join();"), "Android clipboard worker must be joined only after its completion flag is observed");
assert.ok(opentuiPatch.includes("wayland_conversion_started"), "Android blocking join safety must remain tied to the worker completion flag");
assert.ok(opentuiPatch.includes('choices=("aarch64", "x86_64")'), "OpenTUI patcher must explicitly support the two official 64-bit targets");
assert.ok(opentuiPatch.includes('if args.target_arch == "aarch64"'), "AArch64-only TLSDESC fallback must be conditional");
assert.ok(opentuiPatch.includes("x86_64 build still references the AArch64 TLSDESC shim"), "x86_64 patch path must fail if the AArch64 shim remains");
assert.ok(opentuiPatch.includes("shared.link_z_max_page_size = 16384"), "OpenTUI Android shared library must be 16 KB page aligned");
assert.ok(opentuiPatch.includes("shared.link_z_common_page_size = 16384"), "OpenTUI Android shared library must declare the 16 KB common page size");
const tlsShim = fs.readFileSync("patches/opentui/tlsdesc-shim.c", "utf8");
assert.ok(!tlsShim.includes("int pthread_tryjoin_np("), "unsafe pthread_tryjoin_np emulation must not be shipped");

const workflow = fs.readFileSync(".github/workflows/validate.yml", "utf8");
assert.ok(workflow.includes("group: validate-native-${{ github.event.pull_request.number || github.ref }}"), "validation runs for the same PR must share one concurrency group");
assert.ok(workflow.includes("cancel-in-progress: true"), "new PR validation must cancel superseded runs");
assert.ok(workflow.includes("build-x86_64-native:"), "CI must build the complete x86_64 runtime independently");
assert.ok(workflow.includes("libnode-dev"), "CI must install Node-API headers for the x86_64 Parcel watcher build");
assert.ok(workflow.includes("patch-opentui-android.py --target-arch x86_64"), "x86_64 CI must select the architecture-specific OpenTUI patch path");
assert.ok(workflow.includes("x86_64 OpenTUI unexpectedly contains unsupported Bionic TLSDESC relocations"), "x86_64 CI must reject unsupported TLSDESC relocations");
assert.ok(workflow.includes("test ! -e work/opentui-x86_64/packages/native/src/tlsdesc-shim.c"), "x86_64 CI must not compile the AArch64 TLS shim");

for (const token of [
  "https://github.com/anomalyco/opentui.git",
  "tools/supply-chain-lock.json",
  "scripts/ci/build-opencode-bundle.sh",
  "scripts/validate-runtime-archive.sh",
  "scripts/smoke-test-runtime-archive.sh",
  "readelf -h",
  "OpenTUI PT_TLS has initialized data",
  "no PT_TLS segment or TLSDESC relocations",
  "TLSDESC relocations but no PT_TLS segment",
  "gh release create",
  "actions/upload-artifact",
  "gzip -n",
  '"v*"',
  "runtime-metadata-updated",
  "gh api --method POST",
  "needs: [static-checks, native-runtime, build-x86_64-native]",
  "contents: read",
  "contents: write",
  "git merge-base --is-ancestor",
  "release-checksums.json?ref=main",
  "releaseTag",
  "SOURCE_TAG",
  "RELEASE_TAG",
  "releases/download/$RELEASE_TAG/opencode-$VERSION-android-aarch64-bundle.tar.gz",
  "archiveSha256X86_64", "android-x86_64-candidate-$GITHUB_SHA", "android-x86_64-bundle.tar.gz",
  "CI-verified x86_64 archive to the dual-architecture release", "android-x86_64-candidate-$GITHUB_SHA", "sha256sum -c SHA256SUMS", "archiveSha256X86_64", "RELEASE_ASSETS", "report-x86_64.json",
  "Invalid package release tag",
  "ocver.py tag",
  "C04-wq/opencode-termux"
]) assert.ok(workflow.includes(token), "Android build workflow missing " + token);

const watcher = fs.readFileSync(".github/workflows/check-upstream.yml", "utf8");
assert.ok(watcher.includes("anomalyco/opencode/git/matching-refs/tags/v"));
assert.ok(watcher.includes("python3 tools/upstream_tags.py"));
assert.ok(watcher.includes("refs/tags/v"));
assert.ok(watcher.includes("tools/ocver.py current"));
assert.ok(watcher.includes("gh issue create"));
assert.ok(watcher.includes("No physical Termux device testing is required"), "upstream detection must not require physical Termux devices");
assert.ok(!watcher.includes("device smoke tests"), "upstream detection must not request physical device testing");

const validationWorkflow = fs.readFileSync(".github/workflows/validate.yml", "utf8");
assert.ok(validationWorkflow.includes("build-x86_64-native:"), "candidate validation must build the complete x86_64 runtime");
assert.ok(validationWorkflow.includes("Build full x86_64 OpenCode runtime bundle"), "x86_64 candidate must compile the locked OpenCode source, not only OpenTUI");
assert.ok(validationWorkflow.includes("build-native:"), "candidate validation must build the complete ARM64 runtime");
assert.ok(validationWorkflow.includes("Build and verify Android ARM64 runtime"), "ARM64 candidate build must remain an independent CI gate");
assert.ok(validationWorkflow.includes("Package and smoke-test x86_64 candidate"), "x86_64 candidate archive must be validated and smoke-tested");
assert.ok(validationWorkflow.includes("Package and verify the Termux runtime archive"), "ARM64 candidate archive must be validated and smoke-tested");
assert.ok(watcher.includes('cron: "17 */6 * * *"'), "official upstream release detection must run every six hours");
assert.ok(!watcher.includes("contents/package.json"), "upstream version discovery must not rely on the dev branch manifest");

const autoMergeWorkflow = fs.readFileSync(".github/workflows/auto-merge-upstream.yml", "utf8");
for (const token of [
  "workflow_run:",
  "github.event.workflow_run.event == 'workflow_dispatch'",
  "github.event.workflow_run.conclusion == 'success'",
  "github.event.workflow_run.head_sha",
  "github-actions[bot]",
  "tools/supply-chain-lock.json",
  "gh pr ready",
  "gh pr merge",
  "python3 tools/ocver.py tag",
  'git push origin "$RELEASE_TAG"',
  "gh release view",
  "archiveSha256X86_64"
]) assert.ok(autoMergeWorkflow.includes(token), "automatic release gate missing " + token);
const candidateWorkflow = fs.readFileSync(".github/workflows/prepare-upstream-update.yml", "utf8");
assert.ok(candidateWorkflow.includes("anomalyco/opencode/git/matching-refs/tags/v"));
assert.ok(candidateWorkflow.includes("python3 tools/upstream_tags.py"));
assert.ok(candidateWorkflow.includes("source_sha256"));
assert.ok(candidateWorkflow.includes("candidate_only_not_approved_for_release"));
assert.ok(candidateWorkflow.includes('update_available=false'), "an already-current upstream tag must be a successful no-op");
assert.ok(candidateWorkflow.includes('UPDATE_AVAILABLE="$(python3 - "$CURRENT" "$VERSION"'), "candidate workflow must validate versions before deciding whether an update is available");
assert.ok(candidateWorkflow.includes("Only the tag-triggered release workflow"), "only the verified tag workflow may publish installer metadata");
assert.ok(candidateWorkflow.includes('cron: "17 */6 * * *"'), "upstream candidate preparation must run every six hours");
assert.ok(candidateWorkflow.includes("contents: write") && candidateWorkflow.includes("pull-requests: write"), "upstream automation needs narrowly scoped branch and PR permissions");
assert.ok(candidateWorkflow.includes('lock["current"] = version'), "upstream candidate must advance the source lock for CI validation");
assert.ok(candidateWorkflow.includes('entry["source_sha256"] = digest'), "upstream candidate must pin the exact source archive digest");
assert.ok(candidateWorkflow.includes('gh pr create') && candidateWorkflow.includes("--draft"), "upstream automation must open a draft review PR");
assert.ok(candidateWorkflow.includes('gh workflow run validate.yml') && candidateWorkflow.includes('--ref "$BRANCH"'), "GITHUB_TOKEN-created candidate PRs must explicitly dispatch validation against their branch");
assert.ok(candidateWorkflow.includes("dispatching validation again"), "failed draft candidates must be revalidated automatically");
assert.ok(candidateWorkflow.includes('candidate_only_not_approved_for_release'), "automated upstream candidates must remain explicitly unapproved for release");
assert.ok(candidateWorkflow.includes('package_revision"] = 1'), "a new upstream version must start at package revision one");
assert.ok(candidateWorkflow.includes("No physical Termux device testing is required"), "upstream candidates must rely on automated CI rather than physical device tests");
assert.ok(candidateWorkflow.includes("packages/process-daemon/ghostty-revision"), "upstream automation must update the official daemon Ghostty pin");
assert.ok(candidateWorkflow.includes("process_daemon"), "upstream provenance must track the official PTY daemon package");
assert.ok(!candidateWorkflow.includes("Run Termux device smoke tests"), "physical Termux testing must not be a release-candidate requirement");

const installer = fs.readFileSync("install.sh", "utf8");
assert.ok(installer.includes('HASH_FIELD="archiveSha256X86_64"'), "x86_64 installer must select its own published archive digest");
assert.ok(!installer.includes("physical Termux validation"), "installer must not require physical-device validation for x86_64");
assert.ok(installer.includes('export OPENCODE_LAUNCHER="$PREFIX/bin/opencode"'), "managed launcher must pass its public path into the runtime");
const launcher = fs.readFileSync("packing/launcher/opencode", "utf8");
const installer = fs.readFileSync("install.sh", "utf8");
assert.ok(launcher.includes('OPENCODE_LAUNCHER="${OPENCODE_LAUNCHER:-$self}"'), "launcher must preserve the managed public path or fall back to itself");
assert.ok(!launcher.includes('if [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/bin/opencode" ]; then'), "candidate bundles must not hijack an existing production launcher");
assert.ok(launcher.includes('aarch64) BUN_PTY_LIB="$root/librust_pty_arm64.so"'), "ARM64 launcher must preserve the shipped PTY library name");
assert.ok(launcher.includes('x86_64) BUN_PTY_LIB="$root/librust_pty_x86_64.so"'), "x86_64 launcher must select its matching PTY library");
assert.ok(launcher.includes('OPENCODE_PTY_BIN=$root/opencode-pty'), "launcher must point OpenCode at the official daemon");
assert.ok(installer.includes("OPENCODE_TERMUX_AUTOUPDATE"), "installed wrapper must support unattended device-side updates");
assert.ok(installer.includes("21600"), "device auto-update checks must be throttled to six hours");
assert.ok(installer.includes('"$PREFIX/bin/opencode-termux-update"'), "installed wrapper must use the verified project updater");
assert.ok(installer.includes("--version|-v|--help|-h|update|upgrade"), "help/version/update commands must not trigger a surprise update");
for (const token of ["OPENCODE_ROOT", "BUN_PTY_LIB", "OPENCODE_PARCEL_WATCHER_PATH", "--smol", "__OPENCODE_VERSION__"]) {
  assert.ok(launcher.includes(token), "Termux Bun launcher missing " + token);
}

const archiveValidator = fs.readFileSync("scripts/validate-runtime-archive.sh", "utf8");
assert.ok(archiveValidator.includes('PTY_LIBRARY="librust_pty_x86_64.so"'), "archive validator must require the x86_64 PTY library for x86_64 bundles");
assert.ok(archiveValidator.includes("OTHER_PTY_LIBRARY"), "archive validator must reject a mismatched architecture PTY library");
assert.ok(archiveValidator.includes("lib/opencode/opencode-pty.required"), "archive validator must require the official daemon marker");
const archiveSmoke = fs.readFileSync("scripts/smoke-test-runtime-archive.sh", "utf8");
assert.ok(archiveSmoke.includes('EXPECTED_ELF_MACHINE="Advanced Micro Devices X86-64"'), "archive smoke test must validate x86_64 ELF machines");
const deviceTest = fs.readFileSync("scripts/test-termux-device.sh", "utf8");
for (const token of ["uname -m", "librust_pty_arm64.so", "librust_pty_x86_64.so", "x86_64", "watcher.node", "--version", "--help", "sha256sum", "SHA256SUMS", "candidate archive SHA-256 mismatch", "existing OpenCode installation was not modified"]) {
  assert.ok(deviceTest.includes(token), "physical Termux smoke test missing " + token);
}

console.log("Independent Android/Bionic source-build pipeline contract passed.");
