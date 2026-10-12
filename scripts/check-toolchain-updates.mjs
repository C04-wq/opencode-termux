#!/usr/bin/env node
// Opens a reviewable PR when Alpine's latest stable branch advances.
// Runtime package signatures are still verified by apk during the build.
import fs from "node:fs";
import { findStableBranches } from "./alpine-release-branches.mjs";

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

// The release table links stable branches to dl-cdn.alpinelinux.org/alpine/vX.Y/.
// The old parser expected /releases/X.Y on the website itself, so it stopped
// finding branches when the official page linked directly to the mirror.
const branches = findStableBranches(html);
if (!branches.length) throw new Error("No Alpine stable release-branch links found on the official release page");
const latest = branches.at(-1);

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

const muslMatch = builder.match(/^MUSL_VERSION="([^"]+)"$/m);
console.log(`MUSL_PINNED=${muslMatch?.[1] ?? "unknown"}`);
