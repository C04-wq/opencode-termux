#!/usr/bin/env node
// Opens a reviewable PR when Alpine's latest stable branch advances.
// Runtime package signatures are still verified by apk during the build.
import fs from "node:fs";

const builderPath = "scripts/build-android-release.sh";
const builder = fs.readFileSync(builderPath, "utf8");
const currentMatch = builder.match(/^ALPINE_VERSION="(\d+\.\d+)"$/m);
if (!currentMatch) throw new Error("Could not find pinned ALPINE_VERSION in build script");
const current = currentMatch[1];

const response = await fetch("https://alpinelinux.org/releases/", {
  headers: { "user-agent": "opencode-termux-toolchain-updater" },
  signal: AbortSignal.timeout(20000),
});
if (!response.ok) throw new Error(`Alpine release page returned HTTP ${response.status}`);
const html = await response.text();

// Read only release-branch links from the official releases page. Searching all
// page text can mistake prose, archived notes, or edge mentions for stable branches.
const versions = [...html.matchAll(/href=["'](?:https?:\/\/alpinelinux\.org)?\/releases\/(?:v)?(\d+)\.(\d+)\/?(?:["'#?])/gi)]
  .map((m) => ({ major: Number(m[1]), minor: Number(m[2]), text: `${m[1]}.${m[2]}` }))
  .filter((v) => Number.isInteger(v.major) && Number.isInteger(v.minor) && v.major >= 3 && v.minor >= 0);
const unique = [...new Map(versions.map((v) => [v.text, v])).values()];
if (!unique.length) throw new Error("No Alpine stable release-branch links found on the official release page");
unique.sort((a, b) => a.major - b.major || a.minor - b.minor);
const latest = unique.at(-1).text;

if (latest !== current) {
  const updated = builder.replace(/^ALPINE_VERSION="\d+\.\d+"$/m, `ALPINE_VERSION="${latest}"`);
  if (updated === builder) throw new Error("Could not update the pinned Alpine branch");
  fs.writeFileSync(builderPath, updated);
  console.log("ALPINE_UPDATE=true");
  console.log(`ALPINE_CURRENT=${current}`);
  console.log(`ALPINE_LATEST=${latest}`);
} else {
  console.log("ALPINE_UPDATE=false");
  console.log(`Alpine stable branch unchanged: ${current}`);
}

// musl is intentionally not bumped automatically here: its source hash must be
// independently checked before changing the pin. The build fails closed on a
// hash mismatch, and a maintainer should review a new upstream release first.
const muslMatch = builder.match(/^MUSL_VERSION="([^"]+)"$/m);
console.log(`MUSL_PINNED=${muslMatch?.[1] ?? "unknown"}`);
