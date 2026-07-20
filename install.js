#!/usr/bin/env node

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const GITHUB_REPO = "C04-wq/opencode-termux";
const VERSION = require("./package.json").version;
const LIB_DIR = path.join(__dirname, "lib");
const ARCHIVE_URL = `https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/opencode-termux-aarch64.tar.gz`;

async function main() {
  console.log("opencode-termux: Installing for aarch64...");

  if (process.arch !== "arm64") {
    console.error("Error: This package is only for aarch64 (ARM64) architecture.");
    console.error(`Your architecture: ${process.arch}`);
    process.exit(1);
  }

  if (fs.existsSync(path.join(LIB_DIR, "opencode"))) {
    console.log("opencode-termux: Already installed. Skipping download.");
    return;
  }

  fs.mkdirSync(LIB_DIR, { recursive: true });
  const archivePath = path.join(LIB_DIR, "opencode.tar.gz");

  try {
    console.log(`Downloading from ${ARCHIVE_URL}...`);
    execSync(
      `curl -L -f -o "${archivePath}" "${ARCHIVE_URL}"`,
      { stdio: "inherit", timeout: 300000 }
    );
    console.log("Download complete. Extracting...");

    execSync(`tar -xzf "${archivePath}" -C "${LIB_DIR}"`, { stdio: "inherit" });
    fs.unlinkSync(archivePath);

    console.log("opencode-termux installed successfully!");
    console.log("Run: opencode");
  } catch (err) {
    console.error("Installation failed:", err.message);
    console.error("Make sure you have internet access and GitHub is reachable.");
    if (fs.existsSync(archivePath)) fs.unlinkSync(archivePath);
    process.exit(1);
  }
}

main();
