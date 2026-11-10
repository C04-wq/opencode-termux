#!/usr/bin/env node
// Resolve the highest stable OpenCode release across every major version.
// GitHub's /releases/latest intentionally omits the v2 line, so enumerate
// published releases and select the highest stable semver with the ARM64 musl
// asset required by the Termux runtime builder.
const API = "https://api.github.com/repos/anomalyco/opencode/releases?per_page=100";
const ASSET = "opencode-linux-arm64-musl.tar.gz";

export function compareVersions(a, b) {
  const left = a.replace(/^v/, "").split(".").map(Number);
  const right = b.replace(/^v/, "").split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    const difference = (left[i] ?? 0) - (right[i] ?? 0);
    if (difference !== 0) return difference;
  }
  return 0;
}

export function selectRelease(releases) {
  const candidates = releases
    .filter((release) => !release.draft && !release.prerelease)
    .map((release) => {
      const match = /^v?(\d+)\.(\d+)\.(\d+)$/.exec(release.tag_name ?? "");
      if (!match) return null;
      const asset = release.assets?.find((item) => item.name === ASSET);
      if (!asset) return null;
      const digest = asset.digest?.replace(/^sha256:/, "");
      if (!/^[a-f0-9]{64}$/.test(digest ?? "")) {
        throw new Error(`Release ${release.tag_name} has no valid SHA-256 digest for ${ASSET}`);
      }
      return {
        version: `${match[1]}.${match[2]}.${match[3]}`,
        tag: release.tag_name,
        sha256: digest,
        published_at: release.published_at ?? "",
      };
    })
    .filter(Boolean)
    .sort((a, b) => compareVersions(a.version, b.version));
  if (!candidates.length) {
    throw new Error(`No stable OpenCode release with ${ASSET} and a SHA-256 digest was found`);
  }
  return candidates.at(-1);
}

async function main() {
  const token = process.env.GH_TOKEN;
  if (!token) throw new Error("GH_TOKEN is required");
  const releases = [];
  for (let page = 1; page <= 20; page++) {
    const response = await fetch(`${API}&page=${page}`, {
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${token}`,
        "x-github-api-version": "2022-11-28",
      },
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) {
      throw new Error(`GitHub releases API returned HTTP ${response.status}: ${await response.text()}`);
    }
    const batch = await response.json();
    if (!Array.isArray(batch)) throw new Error("GitHub releases API returned an invalid response");
    releases.push(...batch);
    if (batch.length < 100) break;
    if (page === 20) throw new Error("OpenCode release pagination limit exceeded");
  }
  const selected = selectRelease(releases);
  console.log(JSON.stringify(selected));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
