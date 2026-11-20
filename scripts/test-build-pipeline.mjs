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
  "artifacts/bundle/"
]) assert.ok(build.includes(token), "native build script missing " + token);
assert.ok(build.includes("--filter 'opencode'"), "native typecheck must install root workspace development tools");
assert.ok(build.includes('export PATH="$work/host/bun-linux-x64:$PATH"'), "verified host Bun must be available to lifecycle subprocesses");

const pty = fs.readFileSync("scripts/ci/build-rust-pty-android.sh", "utf8");
assert.ok(pty.includes("EXPECTED_COMMIT"), "bun-pty source commit must be pinned and verified");
assert.ok(pty.includes("tools/ocver.py bunpty commit"));
assert.ok(pty.includes("x86_64-linux-android"), "PTY cross-build must map x86_64 to the Android Rust target");
assert.ok(pty.includes('portable-pty = { version = "=0.9.0"'), "Android PTY dependency must be exact-pinned");
assert.ok(pty.includes('cargo update --manifest-path "$SRC/rust-pty/Cargo.toml" -p portable-pty --precise "$portable_pty_version"'), "Cargo lock must be updated only to the exact portable-pty pin");
assert.ok(pty.includes("build --locked --release"), "the PTY build must reject unrecorded dependency resolution");
assert.equal(lock.bun_pty.portable_pty, "0.9.0", "portable-pty Android compatibility pin must be exact");

const watcherBuild = fs.readFileSync("scripts/ci/build-parcel-watcher-android.sh", "utf8");
for (const token of [
  "x86_64-linux-android",
  "src/linux/InotifyBackend.cc",
  "src/unix/legacy.cc",
  "NAPI_VERSION=3",
  "napi_register_module_v1",
  "readelf -h",
  "glibc-linked dependency found"
]) assert.ok(watcherBuild.includes(token), "Android watcher cross-build missing " + token);
assert.ok(watcherBuild.includes("unsupported TARGET_ARCH"), "watcher builder must reject unsupported targets");

const sourcePatch = fs.readFileSync("tools/patch-opencode-source.py", "utf8");
assert.ok(sourcePatch.includes("C04-wq/opencode-termux"), "native updater must target this repository");
assert.ok(sourcePatch.includes("raw.githubusercontent.com/C04-wq/opencode-termux/main/install.sh"), "native updater must use the current installer");
assert.ok(sourcePatch.includes("release-checksums.json"), "native updater must use the installer's pinned metadata");
assert.ok(sourcePatch.includes('exec(["bash", installer], "4 hours")'), "native updater must invoke the Bash installer with Bash");
assert.ok(sourcePatch.includes("actualVersion !== version"), "native and APT update paths must verify the installed version");
assert.ok(sourcePatch.includes('item.abi !== "android"'), "Android targets must never resolve a glibc PTY asset");
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
const tlsShim = fs.readFileSync("patches/opentui/tlsdesc-shim.c", "utf8");
assert.ok(!tlsShim.includes("int pthread_tryjoin_np("), "unsafe pthread_tryjoin_np emulation must not be shipped");

const workflow = fs.readFileSync(".github/workflows/validate.yml", "utf8");
assert.ok(workflow.includes("group: validate-native-${{ github.event.pull_request.number || github.ref }}"), "validation runs for the same PR must share one concurrency group");
assert.ok(workflow.includes("cancel-in-progress: true"), "new PR validation must cancel superseded runs");
assert.ok(workflow.includes("build-x86_64-native:"), "CI must build the x86_64 OpenTUI native library independently");
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
  "OpenTUI PT_TLS segment is missing",
  "gh release create",
  "actions/upload-artifact",
  "gzip -n",
  '"v*"',
  "runtime-metadata-updated",
  "gh api --method POST",
  "needs: [static-checks, native-runtime]",
  "contents: read",
  "contents: write",
  "git merge-base --is-ancestor",
  "release-checksums.json?ref=main",
  "releaseTag",
  "SOURCE_TAG",
  "RELEASE_TAG",
  "releases/download/$RELEASE_TAG/opencode-$VERSION-android-aarch64-bundle.tar.gz",
  "Invalid package release tag",
  "ocver.py tag",
  "C04-wq/opencode-termux"
]) assert.ok(workflow.includes(token), "Android build workflow missing " + token);

const watcher = fs.readFileSync(".github/workflows/check-upstream.yml", "utf8");
assert.ok(watcher.includes("anomalyco/opencode/git/matching-refs/tags/v2."));
assert.ok(watcher.includes("python3 tools/upstream_tags.py"));
assert.ok(watcher.includes("refs/tags/v2."));
assert.ok(watcher.includes("tools/ocver.py current"));
assert.ok(watcher.includes("gh issue create"));
assert.ok(!watcher.includes("contents/package.json"), "upstream version discovery must not rely on the dev branch manifest");

const candidateWorkflow = fs.readFileSync(".github/workflows/prepare-upstream-update.yml", "utf8");
assert.ok(candidateWorkflow.includes("anomalyco/opencode/git/matching-refs/tags/v2."));
assert.ok(candidateWorkflow.includes("python3 tools/upstream_tags.py"));
assert.ok(candidateWorkflow.includes("source_sha256"));
assert.ok(candidateWorkflow.includes("candidate_only_not_approved_for_release"));
assert.ok(candidateWorkflow.includes('update_available=false'), "an already-current upstream tag must be a successful no-op");
assert.ok(candidateWorkflow.includes('UPDATE_AVAILABLE="$(python3 - "$CURRENT" "$VERSION"'), "candidate workflow must validate versions before deciding whether an update is available");
assert.ok(candidateWorkflow.includes("Do not modify release-checksums.json"), "candidate preparation must not publish installer metadata");

const installer = fs.readFileSync("install.sh", "utf8");
assert.ok(installer.includes('export OPENCODE_LAUNCHER="$PREFIX/bin/opencode"'), "managed launcher must pass its public path into the runtime");
const launcher = fs.readFileSync("packing/launcher/opencode", "utf8");
assert.ok(launcher.includes('OPENCODE_LAUNCHER="${OPENCODE_LAUNCHER:-$self}"'), "launcher must preserve the managed public path or fall back to itself");
assert.ok(!launcher.includes('if [ -n "${PREFIX:-}" ] && [ -x "$PREFIX/bin/opencode" ]; then'), "candidate bundles must not hijack an existing production launcher");
for (const token of ["OPENCODE_ROOT", "BUN_PTY_LIB", "OPENCODE_PARCEL_WATCHER_PATH", "--smol", "__OPENCODE_VERSION__"]) {
  assert.ok(launcher.includes(token), "Termux Bun launcher missing " + token);
}

const deviceTest = fs.readFileSync("scripts/test-termux-device.sh", "utf8");
for (const token of ["uname -m", "librust_pty_arm64.so", "watcher.node", "--version", "--help", "existing OpenCode installation was not modified"]) {
  assert.ok(deviceTest.includes(token), "physical Termux smoke test missing " + token);
}

console.log("Independent Android/Bionic source-build pipeline contract passed.");
