#!/usr/bin/env node

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const https = require("https");
const http = require("http");

const GITHUB_REPO = "C04-wq/opencode-termux";
const VERSION = require("./package.json").version;
const LIB_DIR = path.join(__dirname, "lib");
const ARCHIVE_URL = `https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/opencode-termux-aarch64.tar.gz`;

function download(url, dest, redirects = 0) {
  if (redirects > 5) {
    return Promise.reject(new Error("Too many redirects"));
  }
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith("https") ? https : http;
    const req = protocol.get(
      url,
      { headers: { "User-Agent": "opencode-termux-installer" }, timeout: 30000 },
      (res) => {
        if (res.statusCode === 302 || res.statusCode === 301) {
          download(res.headers.location, dest, redirects + 1)
            .then(resolve)
            .catch(reject);
          return;
        }
        if (res.statusCode !== 200) {
          reject(new Error(`Download failed: HTTP ${res.statusCode}`));
          return;
        }
        const file = fs.createWriteStream(dest);
        res.pipe(file);
        file.on("finish", () => {
          file.close(resolve);
        });
        file.on("error", (err) => {
          fs.unlink(dest, () => {});
          reject(err);
        });
      }
    );
    req.on("error", (err) => {
      fs.unlink(dest, () => {});
      reject(err);
    });
    req.on("timeout", () => {
      req.destroy();
      fs.unlink(dest, () => {});
      reject(new Error("Download timeout after 30s"));
    });
  });
}

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
    await download(ARCHIVE_URL, archivePath);
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
