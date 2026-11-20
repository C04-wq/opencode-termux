import fs from "node:fs";
import assert from "node:assert/strict";
const meta = JSON.parse(fs.readFileSync("release-checksums.json", "utf8"));
assert.equal(meta.version, "2.3.2");
assert.equal(meta.sourceRepo, "Spectra010s/opencode-termux");
assert.equal(meta.sourceTag, "v" + meta.version);
assert.equal(meta.runtimeId, "android-bionic-bun-v1");
assert.match(meta.archiveSha256, /^[a-f0-9]{64}$/);
const installer = fs.readFileSync("install.sh", "utf8");
for (const token of [
  "bun ripgrep libc++", "SOURCE_REPO_PIN", "SOURCE_TAG",
  "opencode-$VERSION-android-aarch64-bundle.tar.gz",
  "validate-runtime-archive.sh", "@TERMUX_PREFIX@/lib/opencode",
  "$RUNTIME/bin/opencode", ".opencode-termux-runtime-id", "INSTALLED_RUNTIME_ID", "LATEST_RUNTIME_ID", "chmod 755 \"$LAUNCHER\" \"$UPDATER\" \"$MANAGER\""
]) assert.ok(installer.includes(token), "installer missing native runtime contract: " + token);
assert.ok(!installer.includes('FILES="opencode ld-musl-aarch64.so.1'), "legacy musl runtime must not be installed");
const manager = fs.readFileSync("manager.sh", "utf8");
assert.equal(fs.readFileSync("opencode-termux", "utf8"), manager, "manager entry point must match manager.sh");
for (const token of ["bun rg", "libc++_shared.so", ".opencode-termux-runtime-id", "bin/opencode", "lib/opencode/index.js", "lib/opencode/librust_pty_arm64.so", "lib/opencode/watcher.node"]) {
  assert.ok(manager.includes(token), "doctor missing native dependency: " + token);
}
assert.ok(manager.includes('"$RUNTIME/bin/opencode" --version'), "doctor must execute the native launcher");
const validator = fs.readFileSync("scripts/validate-runtime-archive.sh", "utf8");
for (const token of ["bin/opencode", "lib/opencode/index.js", "librust_pty_arm64.so", "watcher.node", "no-same-owner", "no-same-permissions"]) {
  assert.ok(validator.includes(token), "archive validator missing " + token);
}
const uninstall = fs.readFileSync("uninstall.sh", "utf8");
assert.ok(uninstall.includes('rm -rf "$RUNTIME"'), "uninstaller must remove the complete native bundle");
assert.ok(installer.includes('THIRD_PARTY_NOTICES.md'), "installer must install third-party license notices");
assert.ok(manager.includes("THIRD_PARTY_NOTICES.md"), "doctor must verify installed license notices");
console.log("Native runtime metadata, installer, manager, validator and uninstall contracts passed.");
