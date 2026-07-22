#!/usr/bin/env node
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const VERSION = require("./package.json").version;
const OPENCODE_DIR = path.join(process.env.HOME, ".opencode");
const URL = `https://github.com/C04-wq/opencode-termux/releases/download/v${VERSION}/opencode-termux-aarch64.tar.gz`;
const INTERPRETER = path.join(OPENCODE_DIR, "ld-musl-aarch64.so.1");

if (process.arch !== "arm64") { console.error("Error: aarch64 only."); process.exit(1); }
if (fs.existsSync(path.join(OPENCODE_DIR, "opencode"))) return;

try { execSync("which patchelf", { stdio: "ignore" }); } catch(e) {
  console.log("Installing patchelf...");
  execSync("pkg install patchelf -y", { stdio: "inherit", timeout: 120000 });
}

fs.mkdirSync(OPENCODE_DIR, { recursive: true });
const tmp = path.join(OPENCODE_DIR, "tmp.tar.gz");
try {
  console.log("Downloading opencode...");
  execSync(`curl -L -f -o "${tmp}" "${URL}"`, { stdio: "inherit", timeout: 300000 });
  execSync(`tar -xzf "${tmp}" -C "${OPENCODE_DIR}"`, { stdio: "inherit" });
  fs.unlinkSync(tmp);
  try {
    execSync(`patchelf --set-interpreter "${INTERPRETER}" "${path.join(OPENCODE_DIR, "opencode")}"`, { stdio: "inherit" });
  } catch(e) {}
  console.log("Verifying installation...");
  try {
    const result = execSync(
      `LD_PRELOAD="${INTERPRETER}" LD_LIBRARY_PATH="${OPENCODE_DIR}" ` +
      `SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem ` +
      `"${path.join(OPENCODE_DIR, "opencode")}" --version`,
      { encoding: "utf8", timeout: 15000 }
    );
    if (!result || result.trim().length === 0) throw new Error("Empty response");
    console.log(`Verified: ${result.trim()}`);
  } catch (e) {
    console.log("Verification failed, retrying...");
    try {
      execSync(`patchelf --set-interpreter "${INTERPRETER}" "${path.join(OPENCODE_DIR, "opencode")}"`, { stdio: "inherit" });
    } catch(e2) {}
    try {
      const result = execSync(
        `LD_PRELOAD="${INTERPRETER}" LD_LIBRARY_PATH="${OPENCODE_DIR}" ` +
        `SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem ` +
        `"${path.join(OPENCODE_DIR, "opencode")}" --version`,
        { encoding: "utf8", timeout: 15000 }
      );
      if (!result || result.trim().length === 0) throw new Error("Empty response");
      console.log(`Verified: ${result.trim()}`);
    } catch (e) {
      console.error("Error: opencode is not working.");
      process.exit(1);
    }
  }
  console.log("Done! Run: opencode");
} catch (e) { console.error("Error:", e.message); if (fs.existsSync(tmp)) fs.unlinkSync(tmp); process.exit(1); }
