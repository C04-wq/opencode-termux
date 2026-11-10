#!/usr/bin/env node
// Resolve the newest stable OpenCode release across every major version.
// Select the newest stable tag first, then validate its required asset. Never
// silently fall back to an older version when the newest release is unusable.
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const API = "https://api.github.com/repos/anomalyco/opencode/releases";
const ASSET = "opencode-linux-arm64-musl.tar.gz";
const SEMVER_TAG = /^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;

export function compareVersions(a, b) {
  const left = /^(?:v)?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.exec(a);
  const right = /^(?:v)?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.exec(b);
  if (!left || !right) throw new Error("compareVersions requires valid stable semantic versions");
  for (let i = 1; i <= 3; i++) {
    const difference = BigInt(left[i]) - BigInt(right[i]);
    if (difference < 0n) return -1;
    if (difference > 0n) return 1;
  }
  return 0;
}

export function selectRelease(releases) {
  if (!Array.isArray(releases)) throw new Error("GitHub releases response must be an array");

  const stable = releases
    .filter((release) => release && !release.draft && !release.prerelease)
    .map((release) => {
      const match = SEMVER_TAG.exec(release.tag_name ?? "");
      if (!match) return null;
      return { release, version: match.slice(1).join(".") };
    })
    .filter(Boolean)
    .sort((a, b) => compareVersions(a.version, b.version));

  if (!stable.length) {
    throw new Error("No stable OpenCode release with a v-prefixed semantic version was found");
  }

  const newest = stable.at(-1);
  const release = newest.release;
  const version = newest.version;
  if (!Array.isArray(release.assets)) {
    throw new Error("Newest stable release " + release.tag_name + " has an invalid assets list");
  }

  const asset = release.assets.find((item) => item?.name === ASSET);
  if (!asset) {
    throw new Error("Newest stable release " + release.tag_name + " does not publish required asset " + ASSET + "; refusing to fall back to an older release");
  }

  const digest = /^sha256:([a-f0-9]{64})$/.exec(asset.digest ?? "");
  if (!digest) {
    throw new Error("Newest stable release " + release.tag_name + " has no valid SHA-256 digest for " + ASSET);
  }

  return {
    version,
    tag: release.tag_name,
    sha256: digest[1],
    published_at: release.published_at ?? "",
  };
}

export async function fetchAllReleases({
  token,
  fetchImpl = fetch,
  perPage = 100,
  maxPages = 20,
} = {}) {
  if (!token) throw new Error("GH_TOKEN is required");
  if (!Number.isInteger(perPage) || perPage < 1 || perPage > 100) {
    throw new Error("perPage must be an integer between 1 and 100");
  }
  if (!Number.isInteger(maxPages) || maxPages < 1) {
    throw new Error("maxPages must be a positive integer");
  }

  const releases = [];
  for (let page = 1; page <= maxPages; page++) {
    const url = new URL(API);
    url.searchParams.set("per_page", String(perPage));
    url.searchParams.set("page", String(page));

    const response = await fetchImpl(url, {
      headers: {
        accept: "application/vnd.github+json",
        authorization: "Bearer " + token,
        "x-github-api-version": "2022-11-28",
      },
      signal: AbortSignal.timeout(30000),
    });

    if (!response.ok) {
      let detail = "";
      try { detail = await response.text(); } catch {}
      throw new Error("GitHub releases API returned HTTP " + response.status + (detail ? ": " + detail : ""));
    }

    let batch;
    try {
      batch = await response.json();
    } catch {
      throw new Error("GitHub releases API returned invalid JSON on page " + page);
    }
    if (!Array.isArray(batch)) {
      throw new Error("GitHub releases API returned a non-array response on page " + page);
    }

    releases.push(...batch);
    if (batch.length < perPage) return releases;
  }

  throw new Error("OpenCode release pagination limit exceeded (" + maxPages + " pages)");
}

async function main() {
  const releases = await fetchAllReleases({ token: process.env.GH_TOKEN });
  console.log(JSON.stringify(selectRelease(releases)));
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
