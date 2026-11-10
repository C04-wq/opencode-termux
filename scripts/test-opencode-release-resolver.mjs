import assert from "node:assert/strict";
import { compareVersions, selectRelease } from "./resolve-opencode-release.mjs";

const digest = "a".repeat(64);
const release = (tag, options = {}) => ({
  tag_name: tag,
  draft: false,
  prerelease: false,
  published_at: "2026-11-06T23:37:00Z",
  assets: [{ name: "opencode-linux-arm64-musl.tar.gz", digest: `sha256:${digest}` }],
  ...options,
});

assert.equal(compareVersions("2.2.6", "1.19.5") > 0, true);
assert.equal(compareVersions("2.10.0", "2.9.99") > 0, true);
assert.equal(compareVersions("2.2.6", "2.2.6"), 0);

const selected = selectRelease([
  release("v1.19.5"),
  release("v2.2.5"),
  release("v2.2.6"),
  release("v9.0.0-beta.1", { prerelease: true }),
  release("v8.0.0", { draft: true }),
  release("v7.0.0", { assets: [] }),
]);
assert.equal(selected.version, "2.2.6");
assert.equal(selected.sha256, digest);

assert.throws(
  () => selectRelease([release("v3.0.0", { assets: [{ name: "opencode-linux-arm64-musl.tar.gz" }] })]),
  /no valid SHA-256 digest/,
);
assert.throws(() => selectRelease([]), /No stable OpenCode release/);
console.log("OpenCode release resolver tests passed.");
