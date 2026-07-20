#!/usr/bin/env node
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const VERSION = require("./package.json").version;
const LIB_DIR = path.join(__dirname, "lib");
const URL = `https://github.com/C04-wq/opencode-termux/releases/download/v${VERSION}/opencode-termux-aarch64.tar.gz`;
if (process.arch !== "arm64") { console.error("Error: aarch64 only."); process.exit(1); }
if (fs.existsSync(path.join(LIB_DIR, "opencode"))) return;
fs.mkdirSync(LIB_DIR, { recursive: true });
const tmp = path.join(LIB_DIR, "tmp.tar.gz");
try {
  console.log("Downloading opencode for Termux...");
  execSync(`curl -L -f -o "${tmp}" "${URL}"`, { stdio: "inherit", timeout: 300000 });
  execSync(`tar -xzf "${tmp}" -C "${LIB_DIR}"`, { stdio: "inherit" });
  fs.unlinkSync(tmp);
  const HOME_LIB = path.join(process.env.HOME, ".opencode", "lib");
  fs.mkdirSync(HOME_LIB, { recursive: true });
  for (const f of fs.readdirSync(LIB_DIR)) {
    const dst = path.join(HOME_LIB, f);
    if (!fs.existsSync(dst)) fs.symlinkSync(path.join(LIB_DIR, f), dst);
  }
  console.log("Done! Run: opencode");
} catch (e) { console.error("Failed:", e.message); if (fs.existsSync(tmp)) fs.unlinkSync(tmp); process.exit(1); }
