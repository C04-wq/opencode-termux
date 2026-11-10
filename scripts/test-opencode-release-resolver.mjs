import assert from "node:assert/strict";
import { compareVersions, fetchAllReleases, selectRelease } from "./resolve-opencode-release.mjs";

const digest = "a".repeat(64);
const asset = () => ({ name: "opencode-linux-arm64-musl.tar.gz", digest: `sha256:${digest}` });
const release = (tag, options = {}) => ({
  tag_name: tag,
  draft: false,
  prerelease: false,
  published_at: "2026-11-06T23:37:00Z",
  assets: [asset()],
  ...options,
});

assert.equal(compareVersions("2.2.6", "1.19.5"), 1);
assert.equal(compareVersions("2.10.0", "2.9.99"), 1);
assert.equal(compareVersions("2.2.6", "2.2.6"), 0);
assert.equal(compareVersions("999999999999999999999.0.0", "2.0.0"), 1);
assert.throws(() => compareVersions("2.01.0", "2.1.0"), /valid stable semantic versions/);

const selected = selectRelease([
  release("v1.19.5"),
  release("v2.2.5"),
  release("v2.2.6"),
  release("v9.0.0-beta.1", { prerelease: true }),
  release("v8.0.0", { draft: true }),
  release("v7.0.0", { assets: [] }),
  release("02.0.0"),
]);
assert.equal(selected.version, "2.2.6");
assert.equal(selected.tag, "v2.2.6");
assert.equal(selected.sha256, digest);

// Critical regression: never choose an older release just because the newest
// stable release is missing the required ARM64 musl asset.
assert.throws(
  () => selectRelease([release("v2.2.6"), release("v2.3.0", { assets: [] })]),
  /Newest stable release v2.3.0 does not publish required asset.*refusing to fall back/,
);
assert.throws(
  () => selectRelease([release("v2.3.0", { assets: [{ name: "opencode-linux-arm64-musl.tar.gz" }] })]),
  /no valid SHA-256 digest/,
);
assert.throws(
  () => selectRelease([release("v2.3.0", { assets: [{ name: "opencode-linux-arm64-musl.tar.gz", digest: "sha256:xyz" }] })]),
  /no valid SHA-256 digest/,
);
assert.throws(() => selectRelease([]), /No stable OpenCode release/);
assert.throws(() => selectRelease({}), /must be an array/);

// Pagination: retrieve every page, including a final partial page.
const pageCalls = [];
const paged = await fetchAllReleases({
  token: "test-token",
  perPage: 2,
  fetchImpl: async (url, options) => {
    pageCalls.push({ url: String(url), options });
    const page = new URL(url).searchParams.get("page");
    return { ok: true, json: async () => page === "1" ? [release("v1.0.0"), release("v1.1.0")] : [release("v2.0.0")] };
  },
});
assert.equal(paged.length, 3);
assert.equal(pageCalls.length, 2);
assert.match(pageCalls[0].url, /page=1/);
assert.match(pageCalls[1].url, /page=2/);
assert.equal(pageCalls[0].options.headers.authorization, "Bearer test-token");

await assert.rejects(
  fetchAllReleases({ token: "test-token", fetchImpl: async () => ({ ok: false, status: 403, text: async () => "rate limited" }) }),
  /HTTP 403: rate limited/,
);
await assert.rejects(
  fetchAllReleases({ token: "test-token", fetchImpl: async () => ({ ok: true, json: async () => ({ message: "not an array" }) }) }),
  /non-array response/,
);
await assert.rejects(
  fetchAllReleases({ token: "test-token", fetchImpl: async () => ({ ok: true, json: async () => { throw new Error("bad json"); } }) }),
  /invalid JSON/,
);
await assert.rejects(
  fetchAllReleases({ token: "test-token", perPage: 1, maxPages: 2, fetchImpl: async () => ({ ok: true, json: async () => [release("v1.0.0")] }) }),
  /pagination limit exceeded/,
);
await assert.rejects(fetchAllReleases({}), /GH_TOKEN is required/);

console.log("OpenCode release resolver tests passed.");
