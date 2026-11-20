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

const pty = fs.readFileSync("scripts/ci/build-rust-pty-android.sh", "utf8");
assert.ok(pty.includes("EXPECTED_COMMIT"), "bun-pty source commit must be pinned and verified");
assert.ok(pty.includes("tools/ocver.py bunpty commit"));

const sourcePatch = fs.readFileSync("tools/patch-opencode-source.py", "utf8");
assert.ok(sourcePatch.includes("C04-wq/opencode-termux"), "native updater must target this repository");
assert.ok(sourcePatch.includes("raw.githubusercontent.com/C04-wq/opencode-termux/main/install.sh"), "native updater must use the current installer");
assert.ok(sourcePatch.includes("release-checksums.json"), "native updater must use the installer's pinned metadata");
assert.ok(sourcePatch.includes('exec(["bash", installer], "4 hours")'), "native updater must invoke the Bash installer with Bash");
assert.ok(sourcePatch.includes("actualVersion !== version"), "native and APT update paths must verify the installed version");
assert.ok(sourcePatch.includes('item.abi === "musl" ? "musl" : "glibc"'), "Android ABI must not be passed as a libc target to the upstream pty resolver");
assert.ok(sourcePatch.includes("isCurlMethod(method)"), "curl installation detection must remain type-safe in the upstream uninstall patch");
assert.ok(!sourcePatch.includes("'    if (prefix) return\\n'"), "Termux must not suppress detection of legacy package-managed installations");
assert.ok(!sourcePatch.includes('exec(["sh", installer]'), "Bash installer must never be invoked through sh");

const workflow = fs.readFileSync(".github/workflows/validate.yml", "utf8");
for (const token of [
  "https://github.com/anomalyco/opentui.git",
  "tools/supply-chain-lock.json",
  "scripts/ci/build-opencode-bundle.sh",
  "scripts/validate-runtime-archive.sh",
  "scripts/smoke-test-runtime-archive.sh",
  "readelf -h",
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
assert.ok(watcher.includes("refs/tags/(v2[.]"));
assert.ok(watcher.includes("tools/ocver.py current"));
assert.ok(watcher.includes("gh issue create"));
assert.ok(!watcher.includes("contents/package.json"), "upstream version discovery must not rely on the dev branch manifest");

const candidateWorkflow = fs.readFileSync(".github/workflows/prepare-upstream-update.yml", "utf8");
assert.ok(candidateWorkflow.includes("anomalyco/opencode/git/matching-refs/tags/v2."));
assert.ok(candidateWorkflow.includes("source_sha256"));
assert.ok(candidateWorkflow.includes("candidate_only_not_approved_for_release"));
assert.ok(candidateWorkflow.includes('update_available=false'), "an already-current upstream tag must be a successful no-op");
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
