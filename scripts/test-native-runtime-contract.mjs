import fs from "node:fs";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
const meta = JSON.parse(fs.readFileSync("release-checksums.json", "utf8"));
assert.match(meta.version, /^[0-9]+\.[0-9]+\.[0-9]+$/);
assert.equal(meta.sourceRepo, "C04-wq/opencode-termux", "runtime releases must originate from this repository");
assert.equal(meta.sourceTag, "v" + meta.version);
assert.match(meta.releaseTag, new RegExp("^v" + meta.version.replaceAll(".", "\\.") + "(-[1-9][0-9]*)?$"));
assert.equal(meta.runtimeId, "android-bionic-bun-v1");
assert.match(meta.archiveSha256, /^[a-f0-9]{64}$/);
if (meta.archiveSha256X86_64 !== undefined) assert.match(meta.archiveSha256X86_64, /^[a-f0-9]{64}$/);
const installer = fs.readFileSync("install.sh", "utf8");
assert.ok(installer.includes('x86_64) TARGET_ARCH="x86_64"; HASH_FIELD="archiveSha256X86_64"'), "installer must select the x86_64 release checksum");
assert.ok(installer.includes('aarch64) TARGET_ARCH="aarch64"; HASH_FIELD="archiveSha256"'), "installer must preserve the ARM64 release checksum");
assert.ok(installer.includes('unsupported architecture'), "unsupported architectures must be rejected before package installation");
assert.ok(installer.includes("install_termux_packages()") && installer.includes("termux-change-repo"), "package mirror 404s must include recovery instructions");
assert.ok(!installer.includes("run_quiet pkg install"), "package installation must use the mirror-aware helper");
for (const token of [
  "bun ripgrep libc++", "SOURCE_REPO_PIN", "C04-wq/opencode-termux", "SOURCE_TAG", "RELEASE_TAG",
  "opencode-$VERSION-android-$TARGET_ARCH-bundle.tar.gz", "$RELEASE_TAG", "archiveSha256X86_64", "TARGET_ARCH=\"$TARGET_ARCH\"",
  "validate-runtime-archive.sh", "@TERMUX_PREFIX@/lib/opencode",
  "$RUNTIME/bin/opencode", ".opencode-termux-runtime-id", ".opencode-termux-archive-sha256", ".opencode-termux-release-tag"
]) assert.ok(installer.includes(token), "installer missing native runtime contract: " + token);
assert.ok(!installer.includes('FILES="opencode ld-musl-aarch64.so.1'), "legacy musl runtime must not be installed");
const newline = String.fromCharCode(10);
const launcherStart = 'cat > "$STAGE/opencode-launcher" <<';
const launcherOffset = installer.indexOf(launcherStart);
assert.notEqual(launcherOffset, -1, "installer launcher heredoc is missing");
const launcherBodyStart = installer.indexOf(newline, launcherOffset) + newline.length;
const launcherEnd = newline + "LAUNCHER";
const launcherBodyEnd = installer.indexOf(launcherEnd, launcherBodyStart);
assert.notEqual(launcherBodyEnd, -1, "installer launcher heredoc is not terminated");
const launcherSyntax = spawnSync("bash", ["-n"], { input: installer.slice(launcherBodyStart, launcherBodyEnd), encoding: "utf8" });
assert.equal(launcherSyntax.status, 0, "generated OpenCode launcher has invalid Bash syntax: " + launcherSyntax.stderr);
const sourcePatch = fs.readFileSync("tools/patch-opencode-source.py", "utf8");
for (const token of [
  "https://raw.githubusercontent.com/C04-wq/opencode-termux/main/release-checksums.json",
  "https://raw.githubusercontent.com/C04-wq/opencode-termux/main/install.sh",
  "nativeTermux || detected",
  "OPENCODE_TERMUX_EXPECTED_VERSION", "OPENCODE_TERMUX_EXPECTED_RELEASE_TAG",
  "const termuxLatest = Effect.tryPromise",
]) assert.ok(sourcePatch.includes(token), "official OpenCode updater must use the verified Termux repository: " + token);
for (const token of ["OPENCODE_DISABLE_AUTOUPDATE", "OPENCODE_TERMUX_AUTOUPDATE", "AUTO_UPDATE_SKIP", "update-runtime.sh", "21600", "Verified OpenCode update"]) {
  assert.ok(!installer.includes(token), "launcher/installer must not implement a second update system: " + token);
}
const validator = fs.readFileSync("scripts/validate-runtime-archive.sh", "utf8");
for (const token of ["bin/opencode", "lib/opencode/index.js", "librust_pty_arm64.so", "watcher.node", "no-same-owner", "no-same-permissions"]) {
  assert.ok(validator.includes(token), "archive validator missing " + token);
}
const uninstall = fs.readFileSync("uninstall.sh", "utf8");
assert.ok(uninstall.includes('rm -rf "$RUNTIME"'), "uninstaller must remove the complete native bundle");
assert.ok(installer.includes('THIRD_PARTY_NOTICES.md'), "installer must install third-party license notices");
console.log("Native runtime metadata, installer, validator and uninstall contracts passed.");
